use strict;
use warnings;
use v5.10;

# Un-"\C"-escape a string
# All C single-character escapes (\0, \a, \b, \t, \n, \f, \r, \v, \", \', \\, \?) are unescaped
sub unescape {
	my $s = shift;
	$s =~ s/\\0/\x00/g;
	$s =~ s/\\a/\x07/g;
	$s =~ s/\\b/\x08/g;
	$s =~ s/\\t/\x09/g;
	$s =~ s/\\n/\x0a/g;
	$s =~ s/\\f/\x0c/g;
	$s =~ s/\\r/\x0d/g;
	$s =~ s/\\v/\x0b/g;
	$s =~ s/\\"/\x22/g;
	$s =~ s/\\'/\x27/g;
	$s =~ s/\\\\/\x5c/g;
	$s =~ s/\\\?/\x3f/g;
	$s;
}

# "\xHH"-escape a string
#  All potentially problematic characters are escaped
sub escape {
	my $s = shift;
	$s =~ s/([^ !#-&(-[\]-~])/"\\x" . sprintf("%02x", (ord($1)))/ge;
	$s
}

# The (non-capturing) end of a word (keyword, type, identifier, constant, or string)
#             whitespace   /* comment */   // comment       [](){}.,&*+-!/%<>;=      compar. bitwise
#             vvvvvvvvvvv vvvvvvvvvvvvvvv vvvvvvvvvvvv vvvvvvvvvvvvvvvvvvvvvvvvvvvvv vvvvvvv vvvvvvv
my $end = "(?=[[:space:]]|\\/\\*.*?\\*\\/|\\/\\/.*?\\n|[[\\]()\\{}.,&*+\\-!\\/%<>;=]|[<>=!]=|[&|]{2})";

my $input = do {
	local $/ = undef;
	<>
};

while (length $input) {
	# Whitespace or comments (ignored)
	if ($input =~ s/^([[:space:]]|\/\*.*?\*\/|\/\/.*?\n)//s) {
	# Keywords (break, continue, else, for, if, return, or while)
	} elsif	($input =~ s/^(break|continue|else|for|if|return|while)$end//) {
		say "keyword $1";
	# Types (char, int, long, short, void, or pointers thereto)
	} elsif	($input =~ s/^((?:char|int|long|short|void)\**)$end//) {
		say "type $1";
	# Identifiers (ascii letters, underscored, or (after the first character) digits)
	} elsif ($input =~ s/^([_a-zA-Z][_a-zA-Z0-9]*)$end//) {
		say "identifier $1";
	# Numeric constants (a number, not starting with 0 unless the number is 0)
	} elsif ($input =~ s/^(0|[1-9][0-9]*)$end//) {
		say "constant $1";
	# Character constants (one character or a single-character escape in '')
	} elsif ($input =~ s/^'([^'\\\n]|\\0|\\a|\\b|\\f|\\n|\\r|\\t|\\v|\\'|\\"|\\\\|\\\?)'$end//) {
		say "constant ", ord(unescape $1), "";
	# Strings (zero or more characters or single-character escapes in "")
	} elsif ($input =~ s/^"((?:[^"\\\n]|\\0|\\a|\\b|\\f|\\n|\\r|\\t|\\v|\\'|\\"|\\\\|\\\?)*)"$end//) {
		say "string \"", escape(unescape $1), "\"";
	# Punctuation (one of [](){}.,&*+-!/%<>;=, a comparison, or a bitwise operator)
	} elsif ($input =~ s/^([<>=!]=|[&|<>]{2}|[&|]|[[\]()\{}.,&*+\-~!\/%<>;=])//) {
		say "punctuation $1";
	# Anything else (error)
	} else {
		say STDERR 'c♭: syntax error: unrecognized token near:';
		say STDERR '    ', $input =~ s/(^[^\n]{,76}).*/$1/sr;
		exit 1;
	}
}
