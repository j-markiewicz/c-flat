# Unary operators (except addr) for codegen.sh

# Comments indicate matching IR statements, arguments in bold
# The operand is expected in ret_reg[TYPE] and the result is placed there as well

set -eufo pipefail

# addr TYPE SOURCE
function addr {
	echo $'\t'"lea${suffix[ptr]} $2(%rsp), %${ret_reg[ptr]}"
}

# deref TYPE
function deref {
	echo $'\t'"mov${suffix[$1]} (%${ret_reg[ptr]}, %${sec_reg[ptr]}, ${size[$1]}), %${ret_reg[$1]}"
}

# not TYPE
function not {
	echo $'\t'"test${suffix[$1]} %${ret_reg[$1]}, %${ret_reg[$1]}"
	echo $'\t'"setz %${ret_reg[char]}"
	if [ "$1" != 'char' ]; then 
		echo $'\t'"movz${suffix[char]}${suffix[$1]} %${ret_reg[char]}, %${ret_reg[$1]}"
	fi
}

# inv TYPE
function inv {
	echo $'\t'"not${suffix[$1]} %${ret_reg[$1]}"
}

# neg TYPE
function neg {
	echo $'\t'"neg${suffix[$1]} %${ret_reg[$1]}"
}

# pos TYPE
function pos {
	echo $'\t'"xchg${suffix[$1]} %${ret_reg[$1]}, %${ret_reg[$1]}"
}
