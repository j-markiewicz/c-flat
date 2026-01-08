use strict;
use warnings;
use v5.10;

# Fail lowering with an error message
sub fail {
	my $msg = shift;
	say STDERR "c♭: compiler error: $msg";
	exit 1;
}

# Return a unique name prefixed with the argument
sub namefor {
	state %counters;
	my $prefix = shift;

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
sub alloc {
	state $sp = 0;
	my $type = shift;

	if ($type eq "reset") {
		my $size = $sp;
		$sp = 0;
		return $size;
	}
	
	my $size = sizeof $type;
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

# Lower a value expression
sub lower_value {
	my $var_ty = shift;
	my $var_off = shift;
	my $kind = shift;
	my $value = shift;
	my $type = shift;
	my $register = shift;
	$register = "a" unless defined $register;

	fail "variable $value not declared at time of use" unless $kind ne "identifier" || defined $var_off->{$value};

	fail "invalid string value at type $type" if $kind eq "string" && $type ne "char*";
	fail "variable type $var_ty->{$value} does not match expected type $type" if $kind eq "identifier" && $type ne $var_ty->{$value};

	say "\tget $register const " . typeof($type) . " $value" if $kind eq "constant";
	say "\tget $register symbol $value" if $kind eq "string";
	say "\tget $register var " . typeof($type) . " $var_off->{$value}" if $kind eq "identifier";
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

# Lower an expression
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
		lower_value $var_ty, $var_off, $val_kind, $value, $type;
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
		} elsif ($operation eq "deref") {
			$type = "$type*" if defined $type;
			fail "can't dereference constant" if $val_kind eq "constant";
			fail "can't dereference string literal" if $val_kind eq "string";
			fail "variable type $var_ty->{$value} does not match expected type $type" if $type ne "$var_ty->{$value}";
			lower_value $var_ty, $var_off, $val_kind, $value, $type;
			say "\tderef " . typeof($var_ty->{$value});
		} else {
			lower_value $var_ty, $var_off, $val_kind, $value, $type;
			say "\t$operation " . typeof($type =~ s/\*$//r);
		}
	} elsif ($kind eq "binary") {
		$expr =~ /^(\w+) \((\w+) ([^\)]*)\) \((\w+) ([^\)]*)\)$/;
		my $operation = $1;
		my $val_kind_a = $2;
		my $value_a = $3;
		my $val_kind_b = $4;
		my $value_b = $5;

		lower_value $var_ty, $var_off, $val_kind_a, $value_a, $type;
		lower_value $var_ty, $var_off, $val_kind_b, $value_b, $type, "b";
		say "\t$operation " . typeof($type =~ s/\*$//r);
	} elsif ($kind eq "call") {
		$expr =~ /^(\w+)(.*)$/;
		my $name = $1;
		my $args = $2;
		my $return = $functions->{$name}->[1];
		fail "function return type $return does not match expected type $type" if defined $type && $return ne $type;
		lower_call $functions, $var_ty, $var_off, $name, $args;
	} else {
		fail "unsupported expression kind '$kind'";
	}
}

$_ = do {
	local $/ = undef;
	<>
};

my %functions;

# Lower function declerations
while (s/^fn_decl (\w+) (\S+)(.*)$//m) {
	my $name = $1;
	my $return = $2;
	my $params = $3;
	my $previous_declaration = $functions{$name};

	$functions{$name} = ["declare", $return];
	while ($params =~ s/^ (\S+) (\w+)//) {
		push @{$functions{$name}}, $1;
	}

	assert_signatures_match($previous_declaration, $functions{$name});

	say "symbol $name";
}

# Declare strings
while (s/\(string "(.+)"\)/(string)/) {
	my $name = namefor "STRING";
	say "string $name \"$1\"";
	s/\(string\)/(string $name)/;
}

# Lower function definitions
while (s/(?:\n|^)fn_def (\w+) (\S+)([^\n]*)\n((?:\t[^\n]+(\n|$))*)//s) {
	my $name = $1;
	my $return = $2;
	my $named_params = $3;
	my $body = $4;

	fail "function '$name' defined multiple times" if exists $functions{$name} && ${$functions{$name}}[0] eq "define";
	my $previous_declaration = $functions{$name};
	$functions{$name} = ["define", $return];

	# `type name = expression;` => `type name; name = expression;`
	$body =~ s/^\tvariable (\S+) (\w+) (\{.*\})$/\tvariable $1 $2 undefined\n\tassign $2 $3/mg;
	$body =~ s/^\tvariable (\S+) (\w+) undefined$/\tvariable $1 $2/mg;

	# Collect statements
	my @statements;
	for (split(/\n/, $body)) {
		s/^\s|\s$//g;
		push @statements, $_;
	}

	# Collect and allocate variables (including parameters)
	my %var_off;
	my %var_ty;
	my $params = "";
	while ($named_params =~ s/^ (\S+) (\w+)//) {
		push @{$functions{$name}}, $1;
		fail "parameter '$2' declared multiple times" if exists $var_off{$2};
		$var_off{$2} = alloc $1;
		$var_ty{$2} = $1;
		$params .= " " . typeof($1) . " " . $var_off{$2};
	}

	for (@statements) {
		next if not /^variable (\S+) (\w+)$/;
		fail "variable '$2' declared multiple times" if exists $var_off{$2};
		$var_off{$2} = alloc $1;
		$var_ty{$2} = $1;
	}

	assert_signatures_match($previous_declaration, $functions{$name});

	# Lower function
	my $frame_size = alloc "reset";
	say "function $name $frame_size $return$params";
	for (@statements) {
		if (/^expression \{(\w+) ([^\}]*)\}$/) {
			lower_expression \%functions, \%var_ty, \%var_off, $1, $2;
		} elsif (/^assign (\w+) \{(\w+) ([^\}]*)\}$/) {
			my $dest = $1;
			fail "assigning to undefined variable $dest" unless defined $var_ty{$dest};
			lower_expression \%functions, \%var_ty, \%var_off, $2, $3, $var_ty{$dest};
			say "\tset " . typeof($var_ty{$dest}) . " " . $var_off{$dest};
		} elsif (/^deref_assign (\w+) \{(\w+) ([^\}]*)\}$/) {
			my $dest = $1;
			my $kind = $2;
			my $value = $3;
			fail "deref-assigning to undefined variable $dest" unless defined $var_ty{$dest};
			lower_expression \%functions, \%var_ty, \%var_off, $kind, $value, $var_ty{$dest} =~ s/\*$//r;
			say "\tstore " . typeof($var_ty{$dest}) . " " . $var_off{$dest};
		} elsif (/^return void$/) {
			fail "return without value in function returning $return" if $return ne "void";
			say "\treturn";
		} elsif (/^return \{(\w+) ([^\}]*)\}$/) {
			lower_expression \%functions, \%var_ty, \%var_off, $1, $2, $return;
			say "\treturn";
		} elsif (/^variable (\S+) (\w+)$/) {
			# Already processed
		} else {
			fail "error when lowering '$_'";
		}
	}

	say "\treturn" if $return eq "void";
	say "\tabort";
}
