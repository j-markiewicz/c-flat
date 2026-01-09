# Codegen definitions for codegen.sh

set -eufo pipefail

# Fail code generation with a message indicating the failure's source
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
declare -rA sec_reg=([char]=cl [short]=cx [int]=ecx [long]=rcx [ptr]=rcx)

# Scratch register names by type
declare -rA scratch=([char]=r11b [short]=r11w [int]=r11d [long]=r11 [ptr]=r11)

# Size in bytes of each type
declare -rA size=([char]=1 [short]=2 [int]=4 [long]=8 [ptr]=8)

# Instruction size suffixes by type
declare -rA suffix=([char]=b [short]=w [int]=l [long]=q [ptr]=q)

# Size of the current stack frame
declare -i stack_size=0
