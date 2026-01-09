set -eufo pipefail

function fail {
	echo "c♭: compiler error: codegen failed for '$1'" >&2
	exit 1
}

# Registers in which arguments are passed by type
declare -rA arg_regs=(
	[char]="dil sil dl cl r8b r9b"
	[short]="di si dx cx r8w r9w"
	[int]="edi esi edx ecx r8d r9d"
	[long]="rdi rsi rdx rcx r8 r9"
	[ptr]="rdi rsi rdx rcx r8 r9"
)

# Function return / operation result register names by type
declare -rA ret_reg=([char]=al [short]=ax [int]=eax [long]=rax [ptr]=rax)

# Second operand register for binary operations
declare -rA sec_reg=([char]=dl [short]=dx [int]=edx [long]=rdx [ptr]=rdx)

# Scratch register names by type
declare -rA scratch=([char]=r11b [short]=r11w [int]=r11d [long]=r11 [ptr]=r11)

# Size in bytes of each type
declare -rA size=([char]=1 [short]=2 [int]=4 [long]=8 [ptr]=8)

# Instruction size suffixes by type
declare -rA suffix=([char]=b [short]=w [int]=l [long]=q [ptr]=q)

# Size of the current stack frame
declare -i stack_size=0

# Codegen functions (comments indicate matching IR statements, arguments in bold):

# symbol NAME
function symbol {
	echo ".global $1"
}

# string "STRING"
function string {
	echo ".L$1:"
	echo $'\t'".asciz \"$2\""
}

# function NAME STACK_SIZE RETURN_TYPE [ARGUMENT_TYPE ARGUMENT_POSITION]
function func {
	stack_size=$(( ($2 + 15) / 16 * 16 ))
	echo ".global $1"
	echo "$1:"
	echo $'\t'"pushq %rbp"
	echo $'\t'"movq %rsp, %rbp"
	if [[ $stack_size -gt 0 ]]; then echo $'\t'"sub \$$stack_size, %rsp"; fi
	i=0
	type=''
	for arg in $4; do
		if [[ $type = '' ]]; then
			type=$arg
		else
			regs=(${arg_regs[$type]})
			echo $'\t'"mov${suffix[$type]} %${regs[$i]}, $arg(%rsp)"
			(( i += 1 ))
			type=''
		fi
	done
}

# abort
function abort {
	echo $'\t'"ud2"
}

# return
function gen_return {
	if [[ $stack_size -gt 0 ]]; then echo $'\t'"add \$$stack_size, %rsp"; fi
	echo $'\t'"popq %rbp"
	echo $'\t'"ret"
}

# get REGISTER const TYPE VALUE
function get_const {
	if [ "$1" = "a" ]; then
		echo $'\t'"mov${suffix[$2]} \$$3, %${ret_reg[$2]}"
	elif [ "$1" = "b" ]; then
		echo $'\t'"mov${suffix[$2]} \$$3, %${sec_reg[$2]}"
	else
		fail "$line"
	fi
}

# get REGISTER symbol NAME
function get_symbol {
	if [ "$1" = "a" ]; then
		echo $'\t'"lea${suffix[ptr]} .L$2(%rip), %${ret_reg[ptr]}"
	elif [ "$1" = "b" ]; then
		echo $'\t'"lea${suffix[ptr]} .L$2(%rip), %${sec_reg[ptr]}"
	else
		fail "$line"
	fi
}

# get REGISTER var TYPE SOURCE
function get_var {
	if [ "$1" = "a" ]; then
		echo $'\t'"mov${suffix[$2]} $3(%rsp), %${ret_reg[$2]}"
	elif [ "$1" = "b" ]; then
		echo $'\t'"mov${suffix[$2]} $3(%rsp), %${sec_reg[$2]}"
	else
		fail "$line"
	fi
}

# set TYPE DESTINATION
function gen_set {
	echo $'\t'"mov${suffix[$1]} %${ret_reg[$1]}, $2(%rsp)"
}

# store TYPE DESTINATION
function store {
	echo $'\t'"mov${suffix[ptr]} $2(%rsp), %${scratch[ptr]}"
	echo $'\t'"mov${suffix[$1]} %${ret_reg[$1]}, (%${scratch[ptr]}, %${sec_reg[ptr]}, ${size[$1]})"
}

# call NAME [TYPE KIND SOURCE]
function call {
	i=0
	type=''
	kind=''
	for arg in $2; do
		if [[ $type = '' ]]; then
			type=$arg
		elif [[ $kind = '' ]]; then
			kind=$arg
		else
			regs=(${arg_regs[$type]})
			case "$kind" in
				var) echo $'\t'"mov${suffix[$type]} $arg(%rsp), %${regs[$i]}";;
				const) echo $'\t'"mov${suffix[$type]} \$$arg, %${regs[$i]}";;
				symbol) echo $'\t'"lea${suffix[$type]} .L$arg(%rip), %${regs[$i]}";;
				*) fail "$line";;
			esac
			(( i += 1 ))
			type=''
			kind=''
		fi
	done
	echo $'\t'"xor %rax, %rax"
	echo $'\t'"call $1"
}

# Unary operators (except addr) expect their operand in ret_reg[TYPE] and place
# their result there as well

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

# Binary operators expect their operands in ret_reg[TYPE] and sec_reg[TYPE] and
# place their result in ret_reg[TYPE]

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
	echo $'\t'"mov${suffix[char]} %cl, %${scratch[char]}"
	echo $'\t'"mov${suffix[char]} %${sec_reg[char]}, %cl"
	echo $'\t'"sal${suffix[$1]} %cl, %${ret_reg[$1]}"
	echo $'\t'"mov${suffix[char]} %${scratch[char]}, %cl"
}

# shr TYPE
function shr {
	echo $'\t'"mov${suffix[char]} %cl, %${scratch[char]}"
	echo $'\t'"mov${suffix[char]} %${sec_reg[char]}, %cl"
	echo $'\t'"sar${suffix[$1]} %cl, %${ret_reg[$1]}"
	echo $'\t'"mov${suffix[char]} %${scratch[char]}, %cl"
}

while read -r line; do
	if [[ "$line" =~ ^symbol\ ([[:graph:]]+)$ ]]; then
		symbol "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^string\ ([[:graph:]]+)\ \"(.*)\"$ ]]; then
		string "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^function\ ([[:graph:]]+)\ ([[:digit:]]+)\ ([[:graph:]]+)((\ [[:graph:]]+\ [[:digit:]]+)*)$ ]]; then
		func "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^return$ ]]; then
		gen_return
	elif [[ "$line" =~ ^abort$ ]]; then
		abort
	elif [[ "$line" =~ ^get\ ([[:graph:]]+)\ const\ ([[:graph:]]+)\ ([[:digit:]]+)$ ]]; then
		get_const "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^get\ ([[:graph:]]+)\ symbol\ ([[:graph:]]+)$ ]]; then
		get_symbol "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^get\ ([[:graph:]]+)\ var\ ([[:graph:]]+)\ ([[:graph:]]+)$ ]]; then
		get_var "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^set\ ([[:graph:]]+)\ ([[:digit:]]+)$ ]]; then
		gen_set "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^store\ ([[:graph:]]+)\ ([[:digit:]]+)$ ]]; then
		store "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^addr\ ([[:graph:]]+)\ ([[:digit:]]+)$ ]]; then
		addr "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^(deref|not|inv|neg|pos)\ ([[:graph:]]+)$ ]]; then
		${BASH_REMATCH[1]} "${BASH_REMATCH[@]:2}"
	elif [[ "$line" =~ ^(lt|le|eq|ne|ge|gt)\ ([[:graph:]]+)$ ]]; then
		cmp "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^(add|sub|mul|div|rem|xor|and|or|logical_and|logical_or|shl|shr)\ ([[:graph:]]+)$ ]]; then
		${BASH_REMATCH[1]} "${BASH_REMATCH[@]:2}"
	elif [[ "$line" =~ ^call\ ([[:graph:]]+)((\ [[:graph:]]+\ (symbol|const|var)\ [[:graph:]]+)*)$ ]]; then
		call "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^add\ ([[:graph:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)$ ]]; then
		add "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^sub\ ([[:graph:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)$ ]]; then
		sub "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^mul\ ([[:graph:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)$ ]]; then
		mul "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^div\ ([[:graph:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)$ ]]; then
		div "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^rem\ ([[:graph:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)\ ([[:digit:]]+)$ ]]; then
		rem "${BASH_REMATCH[@]:1}"
	else
		fail "$line"
	fi
done
