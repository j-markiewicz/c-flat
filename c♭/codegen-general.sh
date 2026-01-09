# General codegen functions for codegen.sh

# Comments indicate matching IR statements, arguments in bold

set -eufo pipefail

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

# label NAME
function label {
	echo ".L$1:"
}

# goto NAME
function goto {
	echo $'\t'"jmp .L$1"
}

# branch if TRUE/FALSE TYPE NAME
function branch {
	echo $'\t'"test${suffix[$2]} %${ret_reg[$2]}, %${ret_reg[$2]}"

	if [ "$1" = "true" ]; then
		echo $'\t'"jnz .L$3"
	else
		echo $'\t'"jz .L$3"
	fi
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
