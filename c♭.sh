#!/bin/bash

set -eufo pipefail

verbose=0
use_gcc=false
output='a.out'
libroot='/usr/lib/x86_64-linux-gnu'
gccroot=$(find /usr/lib/gcc/x86_64-linux-gnu/ -maxdepth 1 -mindepth 1 2>/dev/null | sort -rV | head -n 1 || echo '')
print_dir=false
assemble=true
link=true
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Fail compilation
function fail {
	echo "compilation terminated." >&2
	exit 1
}

# Print $2 to stderr if -v/--verbose was passed at least $1 times
function log {
	if [[ $verbose -ge $1 ]]; then
		echo "$2" >&2
	fi
}

# Print the contents of $2 to stderr if -v/--verbose was passed at least $1 times
function log_file {
	if [[ $verbose -ge $1 ]]; then
		perl -pwe 's/^/        | /mg; s/\t/    /g; s/\n*$/\n/' < "$2"
	fi
}

if [[ $(getopt -T > /dev/null; echo "$?") -ne 4 ]]; then
	echo 'c♭: compiler error: non-linux `getopt` detected' >&2
	fail
fi

args=$(getopt -n 'c♭' -l help,verbose,output:,no-assemble,no-link,print-dir,use-gcc,libroot:,gccroot: -o 'hvo:Scp' -- "$@") || fail
eval "set -- ${args}"

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h | --help)
			echo "c♭ [options] file..."
			echo "    Compile a c♭ program."
			echo "    "
			echo "    c♭ compiles each given c♭ source file, then assembles (unless -S is passed)"
			echo "    them and links (unless -c is passed) them together. Intermediate files are"
			echo "    stored in a temporary directory; to inspect the intermediate artifacts, pass"
			echo "    -p to print the directory and prevent automatic deletion. Alternatively,"
			echo "    -vvvvv will also print all intermediate information."
			echo "    "
			echo "    Options:"
			echo "      -h, --help            Display this information"
			echo "      -v, --verbose         Print extra information while compiling"
			echo "                            (more for each time this is passed)"
			echo "      -o, --output <file>   Place the output into <file> (default $output)"
			echo "      -S, --no-assemble     Compile only; do not assemble or link"
			echo "      -c, --no-link         Compile and assemble, but do not link"
			echo "      -p, --print-dir       Print the temporary working directory"
			echo "                            (and don't automatically delete it)"
			echo "      --use-gcc             Use gcc to assemble and link"
			echo "                            (ignores --libroot and --gccroot)"
			echo "      --libroot <dir>       Use system libraries from <dir>"
			echo "                            (default $libroot)"
			echo "      --gccroot <dir>       Use compiler runtime libraries from <dir>"
			echo "                            (default /usr/lib/gcc/x86_64-linux-gnu/<newest>)"
			echo "                            (currently $gccroot)"
			exit 0;;
		-v | --verbose) (( verbose += 1 )); shift;;
		-o | --output) output="$2"; shift 2;;
		-S | --no-assemble) assemble=false; link=false; shift;;
		-c | --no-link) link=false; shift;;
		-p | --print-dir) print_dir=true; shift;;
		--use-gcc) use_gcc=true; shift;;
		--libroot) libroot="$2"; shift 2;;
		--gccroot) gccroot="$2"; shift 2;;
		--) shift; break;;
		*) break;;
	esac
done

log 6 "verbose=$verbose"
log 6 "use_gcc=$use_gcc"
log 6 "output=$output"
log 6 "libroot=$libroot"
log 6 "gccroot=$gccroot"
log 6 "print_dir=$print_dir"
log 6 "assemble=$assemble"
log 6 "link=$link"
log 6 "here=$here"

if [[ $# -eq 0 ]]; then
	echo "c♭: compiler error: no input files" >&2
	fail
fi

if $link && ! $use_gcc && [ ! -d "$gccroot" ]; then
	echo "c♭: compiler error: GCC runtime libraries not found - is gcc installed?" >&2
	echo "    c♭ needs libraries like crtbeginS.o from gcc when linking" >&2
	echo "    use --gccroot to specify their location (usually /usr/lib/gcc/x86_64-linux-gnu/<version>)" >&2
	fail
fi

if $link && ! $use_gcc && [ ! -d "$libroot" ]; then
	echo "c♭: compiler error: C libraries not found - is gcc installed?" >&2
	echo "    c♭ needs libraries like Scrt1.o from gcc when linking" >&2
	echo "    use --libroot to specify their location (usually /usr/lib/x86_64-linux-gnu)" >&2
	fail
fi

workdir="$(mktemp -d)"

if $print_dir; then
	echo "c♭: working in directory: $workdir"
else
	trap "rm -r $workdir" EXIT
fi

for source in "$@"; do
	log 1 "c♭: compiling $source"
	file=$(printf "$source" | base64 -w0 | tr '/+' '_-' | tr -d '=')
	log 6 "    file=$file"
	log 5 "    input ($source):"
	log_file 5 "$source"

	log 2 "    lexing $source"
    perl "-I$here/c♭/" "$here/c♭/lex.pl" < "$source" > "$workdir/$file.tokenstream" || fail
	log 5 "    output ($workdir/$file.tokenstream):"
	log_file 5 "$workdir/$file.tokenstream"

	log 2 "    parsing $source"
    perl "-I$here/c♭/" "$here/c♭/parse.pl" < "$workdir/$file.tokenstream" > "$workdir/$file.ast" || fail
	log 5 "    output ($workdir/$file.ast):"
	log_file 5 "$workdir/$file.ast"

	log 2 "    lowering $source"
    perl "-I$here/c♭/" "$here/c♭/lower.pl" < "$workdir/$file.ast" > "$workdir/$file.ir" || fail
	log 5 "    output ($workdir/$file.ir):"
	log_file 5 "$workdir/$file.ir"

	log 2 "    codegenning $source"
    bash "$here/c♭/codegen.sh" < "$workdir/$file.ir" > "$workdir/$file.S" || fail
	log 5 "    output ($workdir/$file.S):"
	log_file 5 "$workdir/$file.S"

	if $assemble && ! $use_gcc; then
		log 2 "    assembling $source"
		as --64 -O3 "$workdir/$file.S" -o "$workdir/$file.o" || fail
		log 5 "    output ($workdir/$file.o)"
	fi
done

if $use_gcc; then
	log 2 "c♭: assembling and linking"

	find "$workdir" -name '*.S' -printf "'%p' " > "$workdir/gcc.flags"
	echo -n "-O3 -fPIE -pie -z noexecstack " >> "$workdir/gcc.flags"

	if ! $assemble; then
		echo -n "-S " >> "$workdir/gcc.flags"
	elif ! $link; then
		echo -n "-c " >> "$workdir/gcc.flags"
	fi

	echo -n "-o '$output'" >> "$workdir/gcc.flags"

	log 3 "    calling 'gcc @$workdir/gcc.flags'"
	log 4 "    flags ($workdir/gcc.flags):"
	log_file 4 "$workdir/gcc.flags"

	gcc "@$workdir/gcc.flags" || fail
elif $link; then
	log 2 "c♭: linking"

	echo -n "-O3 --build-id --eh-frame-hdr -m elf_x86_64 --hash-style gnu --as-needed " > "$workdir/ld.flags"
	echo -n "-dynamic-linker /lib64/ld-linux-x86-64.so.2 -z noexecstack -pie " >> "$workdir/ld.flags"
	echo -n "'$libroot/Scrt1.o' '$libroot/crti.o' '$gccroot/crtbeginS.o' " >> "$workdir/ld.flags"
	echo -n "'-L$gccroot' '-L$libroot' -L/usr/lib -L/lib/x86_64-linux-gnu -L/lib " >> "$workdir/ld.flags"
	find "$workdir" -name '*.o' -printf "'%p' " >> "$workdir/ld.flags"
	echo -n "-lgcc -lgcc_s -lc -lgcc -lgcc_s " >> "$workdir/ld.flags"
	echo -n "'$gccroot/crtendS.o' '$libroot/crtn.o' " >> "$workdir/ld.flags"
	echo -n "-o '$output'" >> "$workdir/ld.flags"

	log 3 "    calling 'ld @$workdir/ld.flags'"
	log 4 "    flags ($workdir/ld.flags):"
	log_file 4 "$workdir/ld.flags"

	ld "@$workdir/ld.flags" || fail
fi

log 2 "done"
