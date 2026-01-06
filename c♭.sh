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

if [[ $(getopt -T > /dev/null; echo "$?") -ne 4 ]]; then
	echo 'c♭: compiler error: non-linux `getopt` detected' >&2
	fail
fi

args=$(getopt -n 'c♭' -l help,verbose,output:,no-assemble,no-link,print-dir,use-gcc,libroot:,gccroot: -o 'hvo:Scp' -- "$@") || fail
eval "set -- ${args}"

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h | --help)
			echo "Usage: c♭ [options] file..."
			echo "Options:"
			echo "  -h, --help                   Display this information"
			echo "  -v, --verbose                Print extra information while compiling (more for each time this is passed)"
			echo "  -o <file>, --output <file>   Place the output into <file> (default $output)"
			echo "  -S, --no-assemble            Compile only; do not assemble or link"
			echo "  -c, --no-link                Compile and assemble, but do not link"
			echo "  -p, --print-dir              Print the directory containing all temporary files (and don't automaticall delete it)"
			echo "  --use-gcc                    Use gcc to assemble and link, ignores --libroot and --gccroot"
			echo "  --libroot <dir>              Use system libraries from <dir> (default $libroot)"
			echo "  --gccroot <dir>              Use compiler runtime libraries from <dir> (default $gccroot)"
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

log 5 "verbose=$verbose"
log 5 "use_gcc=$use_gcc"
log 5 "output=$output"
log 5 "libroot=$libroot"
log 5 "gccroot=$gccroot"
log 5 "print_dir=$print_dir"
log 5 "assemble=$assemble"
log 5 "link=$link"

if [[ $# -eq 0 ]]; then
	echo "c♭: compiler error: no input files" >&2
	fail
fi

if $link && ! $use_gcc && [ ! -d "$gccroot" ]; then
	echo "c♭: compiler error: GCC runtime libraries not found - is gcc installed?" >&2
	echo "    c♭ needs libraries like crtbegin.o from gcc when linking" >&2
	echo "    use --gccroot to specify their location (usually /usr/lib/gcc/x86_64-linux-gnu/<version>)" >&2
	fail
fi

if $link && ! $use_gcc && [ ! -d "$libroot" ]; then
	echo "c♭: compiler error: C libraries not found - is gcc installed?" >&2
	echo "    c♭ needs libraries like crt1.o from gcc when linking" >&2
	echo "    use --libroot to specify their location (usually /usr/lib/x86_64-linux-gnu)" >&2
	fail
fi

workdir="$(mktemp -d)"

if $print_dir; then
	echo "c♭: working in directory: $workdir"
else
	log 3 "working in directory: $workdir"
	trap "rm -r $workdir" EXIT
fi

for source in "$@"; do
	log 1 "c♭: compiling $source"
	log 2 "    lexing $source"
    perl ./c♭-lex.pl < "$source" > "$workdir/$source.tokenstream" || fail

	log 2 "    parsing $source"
    perl ./c♭-parse.pl < "$workdir/$source.tokenstream" > "$workdir/$source.ast" || fail

	log 2 "    lowering $source"
    perl ./c♭-lower.pl < "$workdir/$source.ast" > "$workdir/$source.ir" || fail

	log 2 "    codegenning $source"
    bash ./c♭-codegen.sh < "$workdir/$source.ir" > "$workdir/$source.S" || fail

	if $assemble && ! $use_gcc; then
		log 2 "    assembling $source"
		as --64 -O3 "$workdir/$source.S" -o "$workdir/$source.o" || fail
	fi
done

if $use_gcc; then
	log 2 "c♭: assembling and linking"

	find "$workdir" -name '*.S' -printf "'%p' " > "$workdir/gcc.flags"
	echo -n "-O3 -fPIE -no-pie -z noexecstack " >> "$workdir/gcc.flags"

	if ! $assemble; then
		echo -n "-S " >> "$workdir/gcc.flags"
	elif ! $link; then
		echo -n "-c " >> "$workdir/gcc.flags"
	fi

	echo -n "-o '$output'" >> "$workdir/gcc.flags"

	log 3 "    calling 'gcc @$workdir/gcc.flags'"
	log 4 "    with '$workdir/gcc.flags': $(cat $workdir/gcc.flags)"

	gcc "@$workdir/gcc.flags" || fail
elif $link; then
	log 2 "c♭: linking"

	echo -n "-O3 --build-id --eh-frame-hdr -m elf_x86_64 --hash-style gnu --as-needed " > "$workdir/ld.flags"
	echo -n "-dynamic-linker /lib64/ld-linux-x86-64.so.2 -z noexecstack " >> "$workdir/ld.flags"
	echo -n "'$libroot/crt1.o' '$libroot/crti.o' '$gccroot/crtbegin.o' " >> "$workdir/ld.flags"
	echo -n "'-L$gccroot' '-L$libroot' -L/usr/lib -L/lib/x86_64-linux-gnu -L/lib/ -L/usr/lib/ " >> "$workdir/ld.flags"
	find "$workdir" -name '*.o' -printf "'%p' " >> "$workdir/ld.flags"
	echo -n "-lgcc -lgcc_s -lc -lgcc -lgcc_s " >> "$workdir/ld.flags"
	echo -n "'$gccroot/crtend.o' '$libroot/crtn.o' " >> "$workdir/ld.flags"
	echo -n "-o '$output'" >> "$workdir/ld.flags"

	log 3 "    calling 'ld @$workdir/ld.flags'"
	log 4 "    with '$workdir/ld.flags': $(cat $workdir/ld.flags)"

	ld "@$workdir/ld.flags" || fail
fi

log 2 "done"
