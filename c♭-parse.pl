use strict;
use warnings;
use v5.10;

sub parse_item;
sub parse_type;
sub parse_identifier;
sub parse_signature;
sub parse_block;
sub parse_statement;
sub parse_value;
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
	my $body = parse_block;

	if (defined $body and not @sig) {
		say "fn_def $name $type";
		for my $statement (@$body) {
			say "\t" . $statement;
		}
	} elsif (defined $body and @sig) {
		say "fn_def $name $type ", join(" ", @sig);
		for my $statement (@$body) {
			say "\t" . $statement;
		}
	} elsif (not defined $body and not @sig) {
		say "fn_decl $name $type";
	} elsif (not defined $body and @sig) {
		say "fn_decl $name $type ", join(" ", @sig);
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
		return;
	} elsif (s/^punctuation \{\n//) {
		while (not s/^punctuation \}\n//) {
			if (not length) { fail "not EOF"; }
			push @statements, parse_statement;
		}
		return \@statements;
	} else {
		fail "; or a block";
	}
}

# Parse a statement (ending with a ;) from $_
# Returns the parsed statement as a string
sub parse_statement {
	my $statement = "";

	if (s/^keyword return\n(?=punctuation ;\n)//) {
		$statement = "return void";
	} elsif (s/^keyword return\n//) {
		$statement = "return " . parse_expression;
	} elsif (s/^type ([\w\*]+)\nidentifier (\w+)\npunctuation =\n//) {
		$statement = "variable $1 $2 " . parse_expression;
	} elsif (s/^type ([\w\*]+)\nidentifier (\w+)\npunctuation \[\nconstant (\d+)\npunctuation \]\n//) {
		$statement = "array $1 $2 $3";
	} elsif (s/^type ([\w\*]+)\nidentifier (\w+)\n//) {
		$statement = "variable $1 $2 undefined";
	} elsif (s/^identifier (\w+)\npunctuation =\n//) {
		$statement = "assign $1 " . parse_expression;
	} elsif (s/^punctuation \*\nidentifier (\w+)\npunctuation =\n//) {
		$statement = "deref_assign $1 " . parse_expression;
	} else {
		$statement = "expression " . parse_expression;
	}

	if (not s/^punctuation ;\n//) {
		fail ";";
	}

	return $statement;
}

# Parse a value (constant, string, or identifier) from $_
# Returns the parsed value in a parenthesised string
sub parse_value {
	if (s/^constant (.+)\n//) {
		return "(constant $1)";
	} elsif (s/^string (.+)\n//) {
		return "(string $1)";
	} elsif (s/^identifier (.+)\n//) {
		return "(identifier $1)";
	} else {
		fail "a value";
	}
}

# Parse an expression (a value, a call, or a binary or unary operation) from $_
# Returns the parsed expression in a braced string
sub parse_expression {
	my %bin_ops = (
		'+' => 'add',
		'-' => 'sub',
		'*' => 'mul',
		'/' => 'div',
		'%' => 'rem',
		'^' => 'xor',
		'&' => 'and',
		'|' => 'or',
		'&&' => 'logical_and',
		'||' => 'logical_or',
		'<' => 'lt',
		'<=' => 'le',
		'==' => 'eq',
		'!=' => 'ne',
		'>=' => 'ge',
		'>' => 'gt',
		'<<' => 'shl',
		'>>' => 'shr'
	);

	my %un_ops = (
		'!' => 'not',
		'~' => 'inv',
		'-' => 'neg',
		'+' => 'pos',
		'*' => 'deref',
		'&' => 'addr'
	);

	if (s/^identifier (\w+)\npunctuation \(\n//) {
		my $expression = "{call $1";

		while (1) {
			if (not length) { fail "not EOF"; }
			$expression .= " " . parse_value unless /^punctuation \)\n/;
			if (s/^punctuation \)\n//) {
				last;
			} elsif (not s/^punctuation ,\n//) {
				fail ", or )";
			}
		}

		return $expression . "}";
	} elsif (/^(constant|string|identifier) (.+)\npunctuation ([<>=!]=|[&|<>]{2}|[&\|*+\-~\/%<>])\n(constant|string|identifier) (.+)\n/) {
		my $expression = "{binary " . $bin_ops{$3} . " " . parse_value . " ";
		s/^punctuation (.+)\n//;
		$expression .= parse_value . "}";
		return $expression;
	} elsif (s/^punctuation ([!~\-+\*&])\n//) {
		return "{unary " . $un_ops{$1} . " " . parse_value . "}";
	} else {
		return "{value " . parse_value . "}";
	}
}
