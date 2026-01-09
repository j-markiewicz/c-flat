# Lower a c♭ AST to IR

use strict;
use warnings;
use v5.10;

use lower;

$_ = do {
	local $/ = undef;
	<>
};

# Function signatures
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
	my %var_ty = ( 'return' => $return );
	my $params = "";
	while ($named_params =~ s/^ (\S+) (\w+)//) {
		push @{$functions{$name}}, $1;
		fail "parameter '$2' declared multiple times" if exists $var_off{$2};
		$var_off{$2} = alloc $1;
		$var_ty{$2} = $1;
		$params .= " " . typeof($1) . " " . $var_off{$2};
	}

	for (@statements) {
		if (/^variable (\S+) (\w+)$/) {
			fail "variable '$2' declared multiple times" if exists $var_off{$2};
			$var_off{$2} = alloc $1;
			$var_ty{$2} = $1;
		} elsif (/^array (\S+) (\w+) (\d+)$/) {
			fail "variable '$2' declared multiple times" if exists $var_off{$2};
			my $off = alloc $1, $3;
			$var_off{$2} = alloc "$1*";
			$var_ty{$2} = "$1*";
			$_ = "array $2 $off";
		}
	}

	assert_signatures_match($previous_declaration, $functions{$name});

	# Deferred statements (until next `end`)
	my @deferred;

	# Lower function
	my $frame_size = alloc "reset";
	say "function $name $frame_size $return$params";

	for (@statements) {
		lower_statement $_, \%functions, \%var_off, \%var_ty, \@deferred;
	}

	say "\treturn" if $return eq "void";
	say "\tabort";
}
