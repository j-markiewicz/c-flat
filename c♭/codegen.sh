# c♭ code generation

set -eufo pipefail

. c♭/codegen-definitions.sh
. c♭/codegen-general.sh
. c♭/codegen-unary.sh
. c♭/codegen-binary.sh

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
	elif [[ "$line" =~ ^label\ ([[:graph:]]+)$ ]]; then
		label "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^goto\ ([[:graph:]]+)$ ]]; then
		goto "${BASH_REMATCH[@]:1}"
	elif [[ "$line" =~ ^branch\ if\ (true|false)\ ([[:graph:]]+)\ ([[:graph:]]+)$ ]]; then
		branch "${BASH_REMATCH[@]:1}"
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
	else
		fail "$line"
	fi
done
