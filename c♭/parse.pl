# Parse a c♭ token stream

use strict;
use warnings;
use v5.10;

use parse;

$_ = do {
	local $/ = undef;
	<>
};

# Parse all items
while (length) {
	parse_item;
}
