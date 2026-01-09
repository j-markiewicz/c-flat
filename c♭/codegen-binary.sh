# Binary operators for codegen.sh

# Comments indicate matching IR statements, arguments in bold
# The operands are expected in ret_reg[TYPE] and sec_reg[TYPE] and the result is
# placed in ret_reg[TYPE]

set -eufo pipefail

# add TYPE
function add {
	echo $'\t'"add${suffix[$1]} %${sec_reg[$1]}, %${ret_reg[$1]}"
}

# sub TYPE
function sub {
	echo $'\t'"sub${suffix[$1]} %${sec_reg[$1]}, %${ret_reg[$1]}"
}

# mul TYPE
function mul {
	echo $'\t'"imul${suffix[$1]} %${sec_reg[$1]}, %${ret_reg[$1]}"
}

# div TYPE
function div {
	echo $'\t'"mov${suffix[$1]} %${sec_reg[$1]}, %${scratch[$1]}"
	case "$1" in
		char) echo $'\t'"cbtw";;
		short) echo $'\t'"cwtd";;
		int) echo $'\t'"cltd";;
		ptr | long) echo $'\t'"cqto";;
		*) fail "$line";;
	esac
	echo $'\t'"idiv${suffix[$1]} %${scratch[$1]}"
}

# rem TYPE
function rem {
	declare -rA rem_reg=([char]=ah [short]=dx [int]=edx [long]=rdx [ptr]=rdx)
	echo $'\t'"mov${suffix[$1]} %${sec_reg[$1]}, %${scratch[$1]}"
	case "$1" in
		char) echo $'\t'"cbtw";;
		short) echo $'\t'"cwtd";;
		int) echo $'\t'"cltd";;
		ptr | long) echo $'\t'"cqto";;
		*) fail "$line";;
	esac
	echo $'\t'"idiv${suffix[$1]} %${scratch[$1]}"
	echo $'\t'"mov${suffix[$1]} %${rem_reg[$1]}, %${ret_reg[$1]}"
}

# xor TYPE
function xor {
	echo $'\t'"xor${suffix[$1]} %${sec_reg[$1]}, %${ret_reg[$1]}"
}

# and TYPE
function and {
	echo $'\t'"and${suffix[$1]} %${sec_reg[$1]}, %${ret_reg[$1]}"
}

# or TYPE
function or {
	echo $'\t'"or${suffix[$1]} %${sec_reg[$1]}, %${ret_reg[$1]}"
}

# logical_and TYPE
function logical_and {
	echo $'\t'"test${suffix[$1]} %${ret_reg[$1]}, %${ret_reg[$1]}"
	echo $'\t'"setnz %${ret_reg[char]}"
	echo $'\t'"test${suffix[$1]} %${sec_reg[$1]}, %${sec_reg[$1]}"
	echo $'\t'"setnz %${sec_reg[char]}"
	echo $'\t'"and${suffix[char]} %${sec_reg[char]}, %${ret_reg[char]}"
	if [ "$1" != 'char' ]; then 
		echo $'\t'"movz${suffix[char]}${suffix[$1]} %${ret_reg[char]}, %${ret_reg[$1]}"
	fi
}

# logical_or TYPE
function logical_or {
	echo $'\t'"test${suffix[$1]} %${ret_reg[$1]}, %${ret_reg[$1]}"
	echo $'\t'"setnz %${ret_reg[char]}"
	echo $'\t'"test${suffix[$1]} %${sec_reg[$1]}, %${sec_reg[$1]}"
	echo $'\t'"setnz %${sec_reg[char]}"
	echo $'\t'"or${suffix[char]} %${sec_reg[char]}, %${ret_reg[char]}"
	if [ "$1" != 'char' ]; then 
		echo $'\t'"movz${suffix[char]}${suffix[$1]} %${ret_reg[char]}, %${ret_reg[$1]}"
	fi
}

# LT/LE/EQ/NE/GE/GT TYPE
function cmp {
	declare -rA cmp=([lt]=l [le]=le [eq]=e [ne]=ne [ge]=ge [gt]=g)
	echo $'\t'"cmp${suffix[$2]} %${sec_reg[$2]}, %${ret_reg[$2]}"
	echo $'\t'"set${cmp[$1]} %${ret_reg[char]}"
	if [ "$2" != 'char' ]; then 
		echo $'\t'"movz${suffix[char]}${suffix[$2]} %${ret_reg[char]}, %${ret_reg[$2]}"
	fi
}

# shl TYPE
function shl {
	echo $'\t'"sal${suffix[$1]} %${sec_reg[char]}, %${ret_reg[$1]}"
}

# shr TYPE
function shr {
	echo $'\t'"sar${suffix[$1]} %${sec_reg[char]}, %${ret_reg[$1]}"
}
