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

	$functions{$name} = [0, $return];
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

	fail "function '$name' defined multiple times" if exists $functions{$name} && ${$functions{$name}}[0] == 1;
	my $previous_declaration = $functions{$name};
	$functions{$name} = [1, $return];

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
		if (s/^expression \{call (\w+)//) {
			my @sig = @{$functions{$1}};
			print "\tcall $1 void";

			my $i = 2;
			while (s/^ \((string|constant|identifier) (\w+)\)//) {
				print " ptr symbol $2" if $1 eq "string";
				print " " . typeof($sig[$i]) . " const $2" if $1 eq "constant";
				print " " . typeof($var_ty{$2}) . " var " . $var_off{$2} if $1 eq "identifier";
				$i += 1;
			}

			if (/^\}$/) {
				say "";
			} else {
				fail "error with function call arguments";
			}
		} elsif (s/^expression \{(.+)\}//) {
			# noop
		} elsif (s/^assign (\w+) \{call (\w+)//) {
			fail "function $2 not declared at time of call" unless defined $functions{$2};
			my @sig = @{$functions{$2}};
			fail "function $2 return type " . $sig[1] . " does not match variable type " . $var_ty{$1} if $sig[1] ne $var_ty{$1};
			print "\tcall $2 " . typeof($var_ty{$1}) . " " . $var_off{$1};

			my $i = 2;
			while (s/^ \((string|constant|identifier) (\w+)\)//) {
				print " ptr symbol $2" if $1 eq "string";
				print " " . typeof($sig[$i]) . " const $2" if $1 eq "constant";
				print " " . typeof($var_ty{$2}) . " var " . $var_off{$2} if $1 eq "identifier";
				$i += 1;
			}

			if (/^\}$/) {
				say "";
			} else {
				fail "error with function call arguments";
			}
		} elsif (/^return void$/) {
			fail "return without value in function returning $return" if $return ne "void";
			say "\treturn void";
		} elsif (/^return \((string|constant) (\w+)\)$/) {
			say "\treturn " . typeof($return) . " symbol $2" if $1 eq "string";
			say "\treturn " . typeof($return) . " const $2" if $1 eq "constant";
		} elsif (/^return \(identifier (\w+)\)$/) {
			fail "returned variable type " . $var_ty{$1} . " does not match function return type $return in $name" if $return ne $var_ty{$1};
			say "\treturn " . typeof($return) . " var " . $var_off{$1};
		} elsif (/^variable (\S+) (\w+)$/) {
			# Already processed
		} elsif (/^assign (\w+) \{value \((constant|string|identifier) (\w+)\)\}$/) {
			print "\tset " . typeof($var_ty{$1}) . " " . $var_off{$1} . " ";
			say "const $3" if $2 eq "constant";
			say "symbol $3" if $2 eq "string";
			say "var " . $var_off{$3} if $2 eq "identifier";
		} elsif (/^assign (\w+) \{unary (\S+) \((constant|string|identifier) (\w+)\)\}$/) {
			print "\t$2 " . typeof($var_ty{$1}) . " " . $var_off{$1} . " ";
			fail "constants in binary operation assignments not supported (yet?)" if $3 eq "constant";
			fail "strings in binary operation assignments not supported (yet?)" if $3 eq "string";
			say $var_off{$4} if $3 eq "identifier";
		} elsif (/^assign (\w+) \{binary (\S+) \((constant|string|identifier) (\w+)\) \((constant|string|identifier) (\w+)\)\}$/) {
			print "\t$2 " . typeof($var_ty{$1}) . " " . $var_off{$1} . " ";
			fail "constants in binary operation assignments not supported (yet?)" if $3 eq "constant";
			fail "strings in binary operation assignments not supported (yet?)" if $3 eq "string";
			print $var_off{$4} . " " if $3 eq "identifier";
			fail "constants in binary operation assignments not supported (yet?)" if $5 eq "constant";
			fail "strings in binary operation assignments not supported (yet?)" if $5 eq "string";
			say $var_off{$6} if $5 eq "identifier";
		} else {
			fail "error when lowering '$_'";
		}
	}

	say "\tabort";
}
