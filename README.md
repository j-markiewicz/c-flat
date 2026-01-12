# c♭

c♭ (*C flat*) is compiler for a subset of the C language written in Bash and Perl.

For usage information, run `./c♭.sh -h`.

## Examples

The included `.c♭` files in `examples/` contain example programs:

- [`hello-world.c♭`](examples/hello-world.c♭) - the classic
- [`multiple-files.c♭`](examples/multiple-files.c♭) and [`math.c♭`](examples/math.c♭) - compilation with multiple source files, mathematical operations, variables
- [`fizz-buzz.c♭`](examples/fizz-buzz.c♭) - while loops and if statements
- [`operators.c♭`](examples/operators.c♭) - all (non-pointer-related) c♭ operators
- [`pointers.c♭`](examples/pointers.c♭) - example operations on pointers
- [`errors.c♭`](examples/errors.c♭) - examples of compiler error handling

## Language

c♭ is a subset of the C language.
It supports most simple operations from C.

### Syntax

In the following descriptions these parts of syntax are used:

- `[...]` - repeat `...` 0 or more times
- `TYPE` - one of the supported types (`void`, `char`, `short`, `int`, `long`, and pointers thereto (`TYPE*`))
- `VALUE` - a simple value (a string literal, an integer constant / character literal, or a variable name (an `IDENTIFIER`))
- `IDENTIFIER` - a name consisting of ASCII letters, digits, or `_` (but not starting with a digit)
- `EXPRESSION` - a value, a unary operation on a value, a binary operation on two values, or a `CALL`
- `CALL` - a function call (`IDENTIFIER([VALUE,])`)
- `BLOCK` - either `;` or zero or more statements (see below) within `{` `}`

The following unary operations are supported (in EXPRESSIONS, they precede a VALUE):

- `!` - boolean not (0 if the value is nonzero, 1 otherwise)
- `~` - bitwise invert (invert each bit in the value)
- `-` - negation (mathematically 2s-complement negate the value)
- `+` - positive (does nothing)
- `*` - dereference a pointer (without offset)
- `&` - take the address of a variable

The following binary operations are supported (in `EXPRESSIONS`, they are between `VALUE`s):

- `+` - add two values
- `-` - subtract the second value from the first
- `*` - multiply two values
- `/` - divide the first value by the second
- `%` - take the remainder of dividing the first value by the second
- `^` - bitwise xor of two values
- `&` - bitwise and of two values
- `|` - bitwise or of two values
- `&&` - logical and of two values <span style="font-size:0.8em;opacity:0.75;">(1 if both are nonzero, 0 otherwise)</span>
- `||` - logical or of two values <span style="font-size:0.8em;opacity:0.75;">(0 if both are zero, 1 otherwise)</span>
- `<` - less-than comparison <span style="font-size:0.8em;opacity:0.75;">(1 if the first value is less than the second value)</span>
- `<=` - less-than-or-equal comparison <span style="font-size:0.8em;opacity:0.75;">(1 if the first value is less than or equal to the second value)</span>
- `==` - equality comparison <span style="font-size:0.8em;opacity:0.75;">(1 if the first value is equal to the second value)</span>
- `!=` - inequality comparison <span style="font-size:0.8em;opacity:0.75;">(1 if the first value is not equal to the second value)</span>
- `>=` - greater-than-or-equal comparison <span style="font-size:0.8em;opacity:0.75;">(1 if the first value is greater than or equal to the second value)</span>
- `>` - greater-than comparison <span style="font-size:0.8em;opacity:0.75;">(1 if the first value is greater than the second value)</span>
- `<<` - arithmetic shift left <span style="font-size:0.8em;opacity:0.75;">(by the amount of bits equal to the second value - between 0 and 255)</span>
- `>>` - arithmetic shift right <span style="font-size:0.8em;opacity:0.75;">(by the amount of bits equal to the second value - between 0 and 255)</span>
- `[VALUE]` - dereference a pointer <span style="font-size:0.8em;opacity:0.75;">(with offset in the square brackets, in units of the size of the pointee type)</span>

### Items

The only supported top-level items are function declerations and definitions - `TYPE IDENTIFIER([TYPE IDENTIFIER,]) BLOCK`.
Functions with a variable number or type of arguments (`...` in signature) are not supported - such functions can be declared and called with only one non-variable signature per c♭ file.
Global variables, preprocessor directives, etc. are not supported.

### Statements

Within function definitions, the following statements are supported:

- `EXPRESSION;` - evaluate `EXPRESSION`, discarding its value
- `return;` - return from void function
- `return EXPRESSION;` - return `EXPRESSION`'s value
- `while (EXPRESSION) BLOCK` - execute `BLOCK` while `EXPRESSION` is nonzero
- `if (EXPRESSION1) BLOCK1 [else if (EXPRESSION2) BLOCK2]` - execute `BLOCK1` (but not any of the other `BLOCK`s) if `EXPRESSION1` is nonzero, execute `BLOCK2` (but not any of the other `BLOCK`s) if `EXPRESSION2` (but not `EXPRESSION1`) is nonzero, etc.
- `if (EXPRESSION1) BLOCK1 [else if (EXPRESSION2) BLOCK2] else BLOCKN` - as above, but execute `BLOCKN` if (and only if) none of the `ESPRESSION`s were nonzero
- `TYPE IDENTIFIER;` - declare a variable named `IDENTIFIER` of type `TYPE`
- `TYPE IDENTIFIER = EXPRESSION;` - as above, and initialize the variable to the result of `EXPRESSION`
- `TYPE IDENTIFIER[VALUE];` - declare array variable (allocates $\text{VALUE} * \mathrm{sizeof}(\text{TYPE})$ bytes of memory on the stack and declares a variable named `IDENTIFIER` of type `TYPE*` with that memory's address as its value; `VALUE` must be an integer literal)
- `IDENTIFIER = EXPRESSION` - set the variable named `IDENTIFIER` to the value of `EXPRESSION`
- `*IDENTIFIER = EXPRESSION` - store the value of `EXPRESSION` to the location pointed to by the variable named `IDENTIFIER`
- `IDENTIFIER[VALUE] = EXPRESSION` - as above, but with an offset of `VALUE` units

## Compiler

c♭ generates code for x86-64 (aka x64/AMD64/Intel 64) using the SYS V ABI.

c♭ requires recent versions of: Bash, Perl, binutils (as and ld) or gcc (with `--use-gcc`), coreutils (nproc, mktemp, sort, head, base64, and tr), find, and util-linux-ng's getopt.

Unless `--use-gcc` is passed, GCC C runtime libraries are required.
By default, the standard GCC installation directories are searched, but this can be overridden with `--libroot` and `--gccroot` (see the `--help` output).
`libroot` must contain `Scrt1.o`, `crti.o`, and `crtn.o`, and `gccroot` must contain `crtbeginS.o` and `crtendS.o`.
`libroot`, `gccroot`, `/lib`, `/usr/lib`, or `/lib/x86_64-linux-gnu` must contain `libgcc`, `libgcc_s`, and `libc` and their dependencies.
The compiled binaries use `/lib64/ld-linux-x86-64.so.2` as the dynamic linker.
However, if `--use-gcc` is passed, GCC's defaults are used instead.

The compiler is structured into four separate phases, all controlled by `c♭.sh`:

- `c♭/lex.pl` converts the source input into a stream of tokens (e.g. `identifier main`, `punctuation ;`)
- `c♭/parse.pl` parses the token stream into an AST
- `c♭/lower.pl` converts the AST into an assemly-like intermediate representation
- `c♭/codegen.sh` converts the IR into assembly

At the end `c♭.sh` uses either binutils' `as` and `ld` or `gcc` to assemble and link the generated assembly files into an executable.

### Example compilation

```c
// From libc
int puts(char* s);

/*
Print a greeting
*/
int main() {
	puts("Hello, World!");
	
	return 0;
}
```

With the above `hello-world.c♭` as the input, the compiler first lexes the input file token-by-token into a token stream.
During this operation, comments are discarded, whitespace in the input is irrelevant, and tokens are classified into one of several categories (`keyword`, `type`, `identifier`, `constant`, `string`, and `punctuation`).

```txt
// int puts(char* s);
type int
identifier puts
punctuation (
type char*
identifier s
punctuation )
punctuation ;

// int main()
type int
identifier main
punctuation (
punctuation )

// {
punctuation {

//     puts("Hello, World!");
identifier puts
punctuation (
string "Hello, World!"
punctuation )
punctuation ;

//     return 0;
keyword return
constant 0
punctuation ;

// }
punctuation }
```

The next step is parsing.
In this phase, the token stream is parsed into a syntax tree resembling the input file.
This representation contains items (`fn_decl` and `fn_def`), and for functions definitions, the statements (e.g. `variable`, `return`, `deref_assign`) that make up their bodies.
Values (string literals, variable names, and integer or character constants) are converted into a normalized form (`(kind value)`, e.g. `(constant 0)` or `(identifier i)`).
Expressions (values, unary or binary operations on values, dereferences, and functions calls) are similarly converted (`{kind ...}`, e.g. `{binary add (identifier i) (constant 1)}` or `{call printf (string "%c = %d") (constant 120) (identifier x)}`).
Other possible c♭ operations have their own statement types, e.g. `expression` for freestanding expressions, `assign` for variable assignment, `variable` for variable declerations, etc.
Statements with associated bodied (`while` and `if`) are parsed into a "flat" form - the start of the body is a statement (e.g. `while expression`) and the end of the body is marked with an `end` statements.
If statements have two `end`s - one for the end of the `if` body and one for the end of the `else` body, even if the source did not contain an explicit `else` (an `if` without an `else` is considered to have an empty `else` body).

```txt
// int puts(char* s);
fn_decl puts int char* s

// int main() { ... }
fn_def main int
    // puts("Hello, World!");
	expression {call puts (string "Hello, World!")}

    // return 0;
	return {value (constant 0)}
```

The next step is lowering.
Here, the AST is converted into an intermediate representation somewhat resembling assembly.
Also, during this step other important compiler operations are performed, such as type checking, stack allocation, etc.
This IR consists of several top-level items (`symbol` for external function declerations, `string` for string literals, `function` for function definitions), and statements within functions.
These statements are mostly small operations (a function call, getting a value, setting a variable, etc.), and mostly operate on two registers (`a` and `b`) and memory (offsets within the stack).

Important statements are `get` and `set`.
`get` takes a register and value (e.g. `const [type] [value]` or `var [type] [offset]`) and stores the value in the given register.
`set` stores the value in the register `a` into the given memory location.
All operators (comparisons, dereferences, math, logic) and some other statements (return) operate on values in the `a` register, and store their result into the `a` register (for binary operators, the second operand is in the `b` register; also note that dereferencing is a binary operator taking a pointer and an offset).
Thus, a c♭ statements like `x = y + 1;` becomes a series of simple IR statements (assuming `x` is stored at `0` and `y` at `4` within the stack and both are `int`s):

| IR statement        | explanation                          |
| ------------------- | ------------------------------------ |
| `get a var int 4`   | load variable y into register a      |
| `get b const int 1` | load a constant 1 into register b    |
| `add int`           | add a and b, storing the result in a |
| `set int 0`         | store register a in variable x       |

The registers `a` and `b` (corresponding in hardware to `*ax` and `*cx`) hold values only temporarily, their contents are not preserved across e.g. function calls.

The result of lowering the `hello-world.c♭` example is:

```txt
// fn_decl puts int char* s
symbol puts

// (string "Hello, World!")
string STRING0 "Hello, World!"

// fn_def main int
function main 0 int

	// expression {call puts (string "Hello, World!")}
	call puts ptr symbol STRING0

	// return {value (constant 0)}
	get a const int 0
	return

	// For runtime error handling of missing return statement in function
	abort
```

The final phase of compilation is code generation.
`c♭/codegen.sh` transforms each IR item/statement into its equivalent x86-64 assembly.
Some IR statements become just one instruction (e.g. `add int` is codegenned as `addl %ecx, %eax`), while some are more complex (e.g. `call`s first set up all arguments and then generate a `call` instruction), and some only generate assembler directives (e.g. `string STRING0 "Hello, World!"` becomes `.LSTRING0: .asciz "Hello, World!"`).
`function` items move the arguments to the stack on entry so that they behave just like regular variables.

The result of code generation for the `hello-world.c♭` is:

```txt
// symbol puts
.global puts

// string STRING0 "Hello, World!"
.LSTRING0:
    .asciz "Hello, World!"

// function main 0 int
.global main
main:
    pushq %rbp
    movq %rsp, %rbp
	// (this is where stack deallocation would happen if there were any parameters/variables in main)
	// (this is where parameter register-to-memory moves would happen if there were any parameters in main)

	// call puts ptr symbol STRING0
    leaq .LSTRING0(%rip), %rdi
    xor %rax, %rax
    call puts

	// get a const int 0
    movl $0, %eax

	// return
	// (this is also where stack deallocation would happen if there were any parameters/variables in main)
    popq %rbp
    ret

	// abort
    ud2
```

This assembly is then assembled using `as` (or `gcc`) and linked with other input files (if any) and standard runtime libraries (with `ld` unless `gcc` is used).

Note that any comments and empty lines in the intermediate artifacts above are only for illustrative purposes and are not part of the compiler phases' input or output. Real in/out-put can be inspected when invoking c♭.sh with `-vvvvv`.
