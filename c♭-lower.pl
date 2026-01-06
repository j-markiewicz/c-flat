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
sub name {
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
sub size {
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
sub type {
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
	
	my $size = size $type;
	while ($sp % $size != 0) {
		$sp += 1;
	}

	my $pos = $sp;
	$sp += $size;
	return $pos;
}

# Extract just the parameter types from a list of parameters
sub param_types {
	my $params = shift;
	my @param_tys;

	while ($params =~ s/^(\w+) (\w+) ?//) {
		push @param_tys, $1;
	}

	return join(" ", @param_tys)
}

$_ = do {
	local $/ = undef;
	<>
};

my %functions;

while (s/^fn_decl (\w+) (.+)$//m) {
	fail "function '$1' declared multiple times" if exists $functions{$1};
	$functions{$1} = param_types $2;
	say "symbol $1";
}

while (s/\(string "(.+)"\)/(string REPLACE_ME)/) {
	my $name = name "STRING";
	say "string $name \"$1\"";
	s/\(string REPLACE_ME\)/(string $name)/;
}

while (s/(?:\n|^)fn_def (\w+) (\w+)([^\n]*)\n((?:\t[^\n]+(\n|$))*)//s) {
	my $name = $1;
	my $return = $2;
	my $named_params = $3;
	my $body = $4;
	my $param_tys = param_types $named_params;

	fail "function '$name' declared multiple times" if exists $functions{$name};
	$functions{$name} = "$return $param_tys";

	my @statements;
	for (split(/\n/, $body)) {
		s/^\s|\s$//g;
		push @statements, $_;
	}

	my %var_off;
	my %var_ty;
	for (@statements) {
		# TODO: collect and alloc all variables (including params), edit $_
	}

	my $params = "";
	while ($named_params =~ s/^(\w+) (\w+) ?//) {
		$params .= " " . type($1) . " " . $var_off{$2};
	}

	$return = type $return;
	my $frame_size = alloc "reset";
	say "function $name $frame_size $return$params";
	for (@statements) {
		if (s/^call (\w+) discard//) {
			print "\tcall $1 discard";

			while (s/^ \((string|constant|identifier) (\w+)\)//) {
				print " ptr symbol $2" if $1 eq "string";
				print " TODO const $2" if $1 eq "constant";
				print " " . $var_ty{$2} . " var " . $var_off{$2} if $1 eq "identifier";
			}

			if (/^$/) {
				say "";
			} else {
				fail "error with function call arguments";
			}
		} elsif (/^return \((string|constant|identifier) (\w+)\)$/) {
			say "\treturn $return symbol $2" if $1 eq "string";
			say "\treturn $return const $2" if $1 eq "constant";
			say "\treturn $return var $2" if $1 eq "identifier";
		}
	}

	say "\tabort";
}
