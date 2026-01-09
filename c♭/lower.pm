# Subroutines for lower.pl

use strict;
use warnings;
use v5.10;

package lower;
our $VERSION = '0.1';
use base 'Exporter';
our @EXPORT = (
	'fail',
	'namefor',
	'sizeof',
	'typeof',
	'alloc',
	'assert_signatures_match',
	'lower_value',
	'lower_call',
	'lower_expression',
	'lower_statement'
);

sub fail;
sub namefor;
sub sizeof;
sub typeof;
sub alloc;
sub assert_signatures_match;
sub lower_value;
sub lower_call;
sub lower_expression;
sub lower_statement;

# Fail lowering with an error message
sub fail {
	my $msg = shift;
	say STDERR "c♭: compiler error: $msg";
	exit 1;
}

# Return a unique name prefixed with the argument
sub namefor {
	my $prefix = shift;

	state %counters;

	if (exists $counters{$prefix}) {
		$counters{$prefix} += 1;
	} else {
		$counters{$prefix} = 0;
	}
	
	return "$prefix$counters{$prefix}";
}

# Get the size (in bytes) of the given type
sub sizeof {
	my $type = shift;

	return 0 if $type eq "void";
	return 1 if $type eq "char";
	return 2 if $type eq "short";
	return 4 if $type eq "int";
	return 8 if $type eq "long";
	return 8 if $type =~ /\*$/;

	fail "unknown type '$type'";
}

# Get the IR type for the given C♭ type
sub typeof {
	my $type = shift;

	return $type if $type =~ /^(void|char|short|int|long)$/;
	return "ptr" if $type =~ /^(void|char|short|int|long)\*+$/;

	fail "unknown type '$type'";
}

# Allocate a variable of the given type on the stack and return its position
# If the given type is "reset", this function's state is instead reset,
# returning the size of the previous stack frame
# A second parameter can be passed to allocate an array of $2 $1s
sub alloc {
	my $type = shift;
	my $amount = shift;
	$amount = 1 unless defined $amount;

	state $sp = 0;

	if ($type eq "reset") {
		my $size = $sp;
		$sp = 0;
		return $size;
	}

	my $size = $amount * sizeof $type;
	fail "can't allocate 0-sized variable" if $size == 0;
	while ($sp % $size != 0) {
		$sp += 1;
	}

	my $pos = $sp;
	$sp += $size;
	return $pos;
}

# Assert that the signatures of \@1 (previous decleration) and \@2 match
sub assert_signatures_match {
	my $a = shift;
	my $b = shift;

	if (defined $a) {
		my $matching = 0;
		if (scalar @$a == scalar @$b) {
			$matching = 1;
			for my $i (1..$#$a) {
				if ($$a[$i] ne $$b[$i]) {
					$matching = 0;
					last;
				}
			}
		}

		fail "function signature '" . join(" ", @$a) . "' does not match '" . join(" ", @$b) . "'" unless $matching;
	}
}

# Lower a value expression, returning the type if known
sub lower_value {
	my $var_ty = shift;
	my $var_off = shift;
	my $kind = shift;
	my $value = shift;
	my $type = shift;
	my $register = shift;
	$type = $var_ty->{$value} if $kind eq "identifier" && not defined $type;
	$type = "char*" if $kind eq "string" && not defined $type;
	$register = "a" unless defined $register;

	fail "variable $value not declared at time of use" unless $kind ne "identifier" || defined $var_off->{$value};
	fail "invalid string value at type $type" if $kind eq "string" && $type ne "char*";
	fail "variable type $var_ty->{$value} does not match expected type $type" if $kind eq "identifier" && $type ne $var_ty->{$value};

	say "\tget $register const " . typeof($type || "long") . " $value" if $kind eq "constant";
	say "\tget $register symbol $value" if $kind eq "string";
	say "\tget $register var " . typeof($type) . " $var_off->{$value}" if $kind eq "identifier";

	$type = "int" if $kind eq "constant" && not defined $type;
	return $type;
}

# Lower a function call expression
sub lower_call {
	my $functions = shift;
	my $var_ty = shift;
	my $var_off = shift;
	my $name = shift;
	my $args = shift;

	fail "function $name not declared at time of call" unless defined $functions->{$name};
	my @sig = @{$functions->{$name}};
	print "\tcall $name";

	my $i = 2;
	while ($args =~ s/^ \((string|constant|identifier) (\w+)\)//) {
		fail "function parameter $2 not declared at time of call" if $1 eq "identifier" && not defined $var_ty->{$2};
		print " ptr symbol $2" if $1 eq "string";
		print " " . typeof($sig[$i]) . " const $2" if $1 eq "constant";
		print " " . typeof($var_ty->{$2}) . " var " . $var_off->{$2} if $1 eq "identifier";
		$i += 1;
	}

	if ($args =~ /^$/) {
		say "";
	} else {
		fail "error with function call arguments";
	}
}

# Lower an expression, returning its type
sub lower_expression {
	my $functions = shift;
	my $var_ty = shift;
	my $var_off = shift;
	my $kind = shift;
	my $expr = shift;
	my $type = shift;

	if ($kind eq "value") {
		$expr =~ /^\((\w+) (.*)\)$/;
		my $val_kind = $1;
		my $value = $2;
		return lower_value $var_ty, $var_off, $val_kind, $value, $type;
	} elsif ($kind eq "deref") {
		$expr =~ /^\((\w+) (.*)\) \((\w+) (.*)\)$/;
		my $off_kind = $1;
		my $offset = $2;
		my $val_kind = $3;
		my $value = $4;

		$type = "$type*" if defined $type;
		fail "can't dereference constant" if $val_kind eq "constant";
		fail "can't dereference string literal" if $val_kind eq "string";
		fail "variable type $var_ty->{$value} does not match expected type $type" if $type ne "$var_ty->{$value}";
		lower_value $var_ty, $var_off, $val_kind, $value, $type;
		lower_value $var_ty, $var_off, $off_kind, $offset, "long", "b";
		say "\tderef " . typeof($var_ty->{$value} =~ s/\*$//r);
		return $var_ty->{$value} =~ s/\*$//r;
	} elsif ($kind eq "unary") {
		$expr =~ /^(\w+) \((\w+) (.*)\)$/;
		my $operation = $1;
		my $val_kind = $2;
		my $value = $3;

		if ($operation eq "addr") {
			fail "can't take address of constant" if $val_kind eq "constant";
			fail "can't take address of string literal" if $val_kind eq "string";
			fail "variable type $var_ty->{$value}* does not match expected type $type" if $type ne "$var_ty->{$value}*";
			say "\taddr " . typeof($var_ty->{$value}) . " " . $var_off->{$value};
			return "$var_ty->{$value}*";
		} else {
			my $val_type = lower_value $var_ty, $var_off, $val_kind, $value, $type || "long";
			say "\t$operation " . typeof($val_type);
			return $val_type;
		}
	} elsif ($kind eq "binary") {
		$expr =~ /^(\w+) \((\w+) ([^\)]*)\) \((\w+) ([^\)]*)\)$/;
		my $operation = $1;
		my $val_kind_a = $2;
		my $value_a = $3;
		my $val_kind_b = $4;
		my $value_b = $5;

		my $type_a = lower_value $var_ty, $var_off, $val_kind_a, $value_a, $type;
		my $type_b = lower_value $var_ty, $var_off, $val_kind_b, $value_b, $type, "b";
		$type = $type || $type_a || $type_b || "long";
		say "\t$operation " . typeof($type);
		return $type;
	} elsif ($kind eq "call") {
		$expr =~ /^(\w+)(.*)$/;
		my $name = $1;
		my $args = $2;
		my $return = $functions->{$name}->[1];
		fail "function return type $return does not match expected type $type" if defined $type && $return ne $type;
		lower_call $functions, $var_ty, $var_off, $name, $args;
		return $return;
	} else {
		fail "unsupported expression kind '$kind'";
	}

	fail "expression has unknown type";
}

# Lower a statement
sub lower_statement {
	my $statement = shift;
	my $functions = shift;
	my $var_off = shift;
	my $var_ty = shift;
	my $deferred = shift;

	if (/^expression \{(\w+) ([^\}]*)\}$/) {
		lower_expression $functions, $var_ty, $var_off, $1, $2;
	} elsif (/^end$/) {
		say (pop @$deferred);
	} elsif (/^while \{(\w+) ([^\}]*)\}$/) {
		my $start_label = namefor "WHILE_START";
		my $end_label = namefor "WHILE_END";
		push @$deferred, "\tgoto $start_label\n\tlabel $end_label";
		say "\tlabel $start_label";
		my $type = lower_expression $functions, $var_ty, $var_off, $1, $2;
		say "\tbranch if false " . typeof($type) . " $end_label";
	} elsif (/^if \{(\w+) ([^\}]*)\}$/) {
		my $start_label = namefor "IF_START";
		my $else_label = namefor "IF_ELSE";
		my $end_label = namefor "IF_END";
		push @$deferred, "\tlabel $end_label";
		push @$deferred, "\tgoto $end_label\n\tlabel $else_label";
		say "\tlabel $start_label";
		my $type = lower_expression $functions, $var_ty, $var_off, $1, $2;
		say "\tbranch if false " . typeof($type) . " $else_label";
	} elsif (/^assign (\w+) \{(\w+) ([^\}]*)\}$/) {
		my $dest = $1;
		fail "assigning to undefined variable $dest" unless defined $var_ty->{$dest};
		lower_expression $functions, $var_ty, $var_off, $2, $3, $var_ty->{$dest};
		say "\tset " . typeof($var_ty->{$dest}) . " " . $var_off->{$dest};
	} elsif (/^deref_assign (\w+) \((constant|identifier) (\w+)\) \{(\w+) ([^\}]*)\}$/) {
		my $dest = $1;
		my $off_kind = $2;
		my $off_value = $3;
		my $kind = $4;
		my $value = $5;
		fail "deref-assigning to undefined variable $dest" unless defined $var_ty->{$dest};
		lower_expression $functions, $var_ty, $var_off, $kind, $value, $var_ty->{$dest} =~ s/\*$//r;
		lower_value $var_ty, $var_off, $off_kind, $off_value, "long", "b";
		my $deref_type = $var_ty->{$dest} =~ s/\*$//r;
		say "\tstore " . typeof($var_ty->{$dest} =~ s/\*$//r) . " " . $var_off->{$dest};
	} elsif (/^return void$/) {
		fail "return without value in function returning $var_ty->{'return'}" if $var_ty->{'return'} ne "void";
		say "\treturn";
	} elsif (/^return \{(\w+) ([^\}]*)\}$/) {
		lower_expression $functions, $var_ty, $var_off, $1, $2, $var_ty->{'return'};
		say "\treturn";
	} elsif (/^array (\w+) (\d+)$/) {
		say "\taddr ptr $2";
		say "\tset ptr $var_off->{$1}";
	} elsif (/^variable (\S+) (\w+)$/) {
		# Already processed
	} else {
		fail "error when lowering '$_'";
	}
}

1;
