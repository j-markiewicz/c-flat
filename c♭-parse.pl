use strict;
use warnings;
use v5.10;

sub parse_item;
sub parse_type;
sub parse_identifier;
sub parse_signature;
sub parse_block;
sub parse_statement;
sub parse_expression;

# Fail parsing with an error message describing what was expected
sub fail {
	my $expected = shift;
	say STDERR "c♭: parsing error: expected $expected, got ", s/(^[^\n]{,76}).*/$1/sr;
	exit 1;
}

$_ = do {
	local $/ = undef;
	<>
};

while (length) {
	parse_item;
}

# Parse an item (a function decleration or definition) from $_
# Outputs the item (fn_decl or fn_def) including all relevant information
sub parse_item {
	my $type = parse_type;
	my $name = parse_identifier;
	my @sig = parse_signature;
	my @body = parse_block;

	if (@body and not @sig) {
		say "fn_def $name $type";
		for my $statement (@body) {
			say "\t" . $statement;
		}
	} elsif (@body and @sig) {
		say "fn_def $name $type ", join(",", @sig);
		for my $statement (@body) {
			say "\t" . $statement;
		}
	} elsif (not @body and not @sig) {
		say "fn_decl $name $type";
	} elsif (not @body and @sig) {
		say "fn_decl $name $type ", join(",", @sig);
	} else {
		fail "item";
	}
}

# Parse a type from $_
# Returns the parsed type as a string
sub parse_type {
	if (s/^type (.+)\n//) {
		return $1;
	} else {
		fail "type";
	}
}

# Parse an identifier from $_
# Returns the parsed identifier as a string
sub parse_identifier {
	if (s/^identifier (.+)\n//) {
		return $1;
	} else {
		fail "identifier";
	}
}

# Parse a function signature (type-identifier pairs in parentheses) from $_
# Returns the list of parsed parameters
sub parse_signature {
	my @sig;

	if (not s/^punctuation \(\n//) {
		fail "(";
	}

	if (s/^type (.+)\nidentifier (.+)\n//) {
		push @sig, "$1 $2";
	} elsif (s/^punctuation \)\n//) {
		return @sig;
	} else {
		fail "type or )";
	}

	while (length) {
		if (s/^punctuation ,\ntype (.+)\nidentifier (.+)\n//) {
			push @sig, "$1 $2";
		} elsif (s/^punctuation \)\n//) {
			return @sig;
		} else {
			fail ", or )";
		}
	}
}

# Parse a block (a list of statements in curly braces) from $_
# Returns the list of statements
sub parse_block {
	my @statements;

	if (s/^punctuation ;\n//) {
		return @statements;
	} elsif (s/^punctuation \{\n//) {
		while (not s/^punctuation \}\n//) {
			if (not length) { fail "not EOF"; }
			push @statements, parse_statement;
		}
		return @statements;
	} else {
		fail "; or a block";
	}
}

# Parse a statement (ending with a ;) from $_
# Returns the parsed statement as a string
sub parse_statement {
	my $statement = "";

	if (s/^identifier (.+)\npunctuation \(\n//) {
		$statement .= "call $1 discard";
		while (1) {
			if (not length) { fail "not EOF"; }
			$statement .= " " . parse_expression;
			if (s/^punctuation \)\n//) {
				last;
			} elsif (not s/^punctuation ,\n//) {
				fail ", or )";
			}
		}
	} elsif (s/^keyword return\n//) {
		$statement .= "return " . parse_expression;
	} else {
		fail "a statement";
	}

	if (not s/^punctuation ;\n//) {
		fail ";";
	}

	return $statement;
}

# Parse an expression from $_
# Returns the parsed expression in a braced string
sub parse_expression {
	if (s/^constant (.+)\n//) {
		return "(constant $1)";
	} elsif (s/^string (.+)\n//) {
		return "(string $1)";
	} elsif (s/^identifier (.+)\n//) {
		return "(identifier $1)";
	} else {
		fail "an expression";
	}
}
