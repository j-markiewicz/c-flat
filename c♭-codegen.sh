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

# Return register by type
declare -rA ret_reg=([char]=al [short]=ax [int]=eax [long]=rax [ptr]=rax)

# Size in bytes of each type
declare -rA size=([char]=1 [short]=2 [int]=4 [long]=8 [ptr]=8)

# Instruction size suffixes by type
declare -rA suffix=([char]=b [short]=w [int]=l [long]=q [ptr]=q)

# Scratch register names by type
declare -rA scratch=([char]=r11b [short]=r11w [int]=r11d [long]=r11 [ptr]=r11)

# Size of the current stack frame
declare -i stack_size=0

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

# return TYPE const VALUE
function return_const {
	echo $'\t'"mov${suffix[$1]} \$$2, %${ret_reg[$1]}"
	if [[ $stack_size -gt 0 ]]; then echo $'\t'"add \$$stack_size, %rsp"; fi
	echo $'\t'"popq %rbp"
	echo $'\t'"ret"
}

# return TYPE symbol VALUE
function return_symbol {
	echo $'\t'"lea${suffix[$1]} .L$2(%rip), %${ret_reg[$1]}"
	if [[ $stack_size -gt 0 ]]; then echo $'\t'"add \$$stack_size, %rsp"; fi
	echo $'\t'"popq %rbp"
	echo $'\t'"ret"
}

# return TYPE var SOURCE
function return_var {
	echo $'\t'"mov${suffix[$1]} $2(%rsp), %${ret_reg[$1]}"
	if [[ $stack_size -gt 0 ]]; then echo $'\t'"add \$$stack_size, %rsp"; fi
	echo $'\t'"popq %rbp"
	echo $'\t'"ret"
}

# set TYPE DESTINATION const VALUE
function set_const {
	echo $'\t'"mov${suffix[$1]} \$$3, $2(%rsp)"
}

# set TYPE DESTINATION symbol NAME
function set_symbol {
	echo $'\t'"lea${suffix[$1]} .L$3(%rip), $2(%rsp)"
}

# set TYPE DESTINATION var SOURCE
function set_var {
	echo $'\t'"mov${suffix[$1]} $3(%rsp), %${scratch[$1]}"
	echo $'\t'"mov${suffix[$1]} %${scratch[$1]}, $2(%rsp)"
}

# call NAME void [TYPE KIND SOURCE]
function call_void {
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

# call NAME TYPE DESTINATION [TYPE KIND SOURCE]
function call {
	store=$'\t'"mov${suffix[$2]} %${ret_reg[$2]}, $3(%rsp)"
	call_void "$1" "$4"
	echo "$store"
}

# add TYPE DESTINATION SOURCE_A SOURCE_B
function add {
	echo $'\t'"mov${suffix[$1]} $3(%rsp), %${scratch[$1]}"
	echo $'\t'"add${suffix[$1]} $4(%rsp), %${scratch[$1]}"
	echo $'\t'"mov${suffix[$1]} %${scratch[$1]}, $2(%rsp)"
}

# sub TYPE DESTINATION SOURCE_A SOURCE_B
function sub {
	echo $'\t'"mov${suffix[$1]} $3(%rsp), %${scratch[$1]}"
	echo $'\t'"sub${suffix[$1]} $4(%rsp), %${scratch[$1]}"
	echo $'\t'"mov${suffix[$1]} %${scratch[$1]}, $2(%rsp)"
}

# mul TYPE DESTINATION SOURCE_A SOURCE_B
function mul {
	echo $'\t'"mov${suffix[$1]} $3(%rsp), %${scratch[$1]}"
	echo $'\t'"imul${suffix[$1]} $4(%rsp), %${scratch[$1]}"
	echo $'\t'"mov${suffix[$1]} %${scratch[$1]}, $2(%rsp)"
}

# div TYPE DESTINATION SOURCE_A SOURCE_B
function div {
	echo $'\t'"mov${suffix[$1]} $3(%rsp), %${ret_reg[$1]}"
	case "$1" in
		char) echo $'\t'"cbtw";;
		short) echo $'\t'"cwtd";;
		int) echo $'\t'"cltd";;
		ptr | long) echo $'\t'"cqto";;
		*) fail "$line";;
	esac
	echo $'\t'"idiv${suffix[$1]} $4(%rsp)"
	echo $'\t'"mov${suffix[$1]} %${ret_reg[$1]}, $2(%rsp)"
}

# rem TYPE DESTINATION SOURCE_A SOURCE_B
function rem {
	declare -rA rem_reg=([char]=ah [short]=dx [int]=edx [long]=rdx [ptr]=rdx)
	echo $'\t'"mov${suffix[$1]} $3(%rsp), %${ret_reg[$1]}"
	case "$1" in
		char) echo $'\t'"cbtw";;
		short) echo $'\t'"cwtd";;
		int) echo $'\t'"cltd";;
		ptr | long) echo $'\t'"cqto";;
		*) fail "$line";;
	esac
	echo $'\t'"idiv${suffix[$1]} $4(%rsp)"
	echo $'\t'"mov${suffix[$1]} %${rem_reg[$1]}, $2(%rsp)"
}

while read -r line; do
	if [[ "$line" =~ ^symbol\ ([[:graph:]]+)$ ]]; then
		symbol "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^string\ ([[:graph:]]+)\ \"(.*)\"$ ]]; then
		string "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^function\ ([[:graph:]]+)\ ([[:digit:]]+)\ ([[:graph:]]+)((\ [[:graph:]]+\ [[:digit:]]+)*)$ ]]; then
		func "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^return\ void$ ]]; then
		return_const "ptr" "0"
	elif [[ "$line" =~ ^return\ ([[:graph:]]+)\ const\ ([[:graph:]]+)$ ]]; then
		return_const "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^return\ ([[:graph:]]+)\ symbol\ ([[:graph:]]+)$ ]]; then
		return_symbol "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^return\ ([[:graph:]]+)\ var\ ([[:graph:]]+)$ ]]; then
		return_var "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^abort$ ]]; then
		abort "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^set\ ([[:graph:]]+)\ ([[:digit:]]+)\ const\ ([[:graph:]]+)$ ]]; then
		set_const "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^set\ ([[:graph:]]+)\ ([[:digit:]]+)\ symbol\ ([[:graph:]]+)$ ]]; then
		set_symbol "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^set\ ([[:graph:]]+)\ ([[:digit:]]+)\ var\ ([[:graph:]]+)$ ]]; then
		set_var "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^call\ ([[:graph:]]+)\ void((\ [[:graph:]]+\ (symbol|const|var)\ [[:graph:]]+)*)$ ]]; then
		call_void "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^call\ ([[:graph:]]+)\ ([[:graph:]]+)\ ([[:digit:]]+)((\ [[:graph:]]+\ (symbol|const|var)\ [[:graph:]]+)*)$ ]]; then
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
