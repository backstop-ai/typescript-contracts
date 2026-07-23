#!/bin/sh
# TS contract-signature -> ast-grep pattern compiler. Infers the TS declaration kind
# from the leading token and emits a param/RHS-insensitive structural pattern that
# matches the declaration even when export-wrapped or async (ast-grep searches all
# nodes and tolerates leading modifiers).
sig="$1"; [ -z "$sig" ] && sig=$(cat)
# strip a trailing // comment, then trim
sig=$(printf '%s' "$sig" | sed 's://.*$::')
trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
sig=$(trim "$sig")
# Quote-style is semantically inert for TS string-literal types: 'main' and "main" are the
# SAME type. ast-grep's pattern match is quote-SENSITIVE, so a single-quoted declaration
# would spuriously miss double-quoted code (and vice versa). Normalize single-quoted string
# literals to the TS-canonical double quote (the prettier/eslint default the emitted pattern
# matches against) so the contract is checked by TYPE, not by an author's quote preference.
sig=$(printf '%s' "$sig" | sed "s/'\\([^']*\\)'/\"\\1\"/g")
fail() {
  printf '%s\n' "unsupported TypeScript contract signature: $sig" >&2
  printf '%s\n' "expected exactly one function, type, interface, const, or class declaration" >&2
  exit 2
}
ast=$(ast-grep run --lang ts --pattern "$sig" --debug-query=ast /dev/null 2>&1 || true)
printf '%s\n' "$ast" | grep -q 'ERROR' && fail
[ "$(printf '%s\n' "$ast" | grep -c '^  [[:alnum:]_].* (')" -eq 1 ] || fail
case "$sig" in
  "type "*)
    body=$(trim "${sig#type }"); name=${body%%[ =]*}
    [ -n "$name" ] && printf '%s' "$body" | grep -q '=' || fail
    printf 'type %s = $$$' "$name" ;;
  "interface "*)
    body=$(trim "${sig#interface }"); name=${body%%[ {<]*}
    [ -n "$name" ] && printf '%s' "$body" | grep -Eq '\{.*\};?[[:space:]]*$' || fail
    printf 'interface %s { $$$ }' "$name" ;;
  "function "*)
    body=$(trim "${sig#function }"); name=$(trim "${body%%(*}")
    [ -n "$name" ] && printf '%s' "$body" | awk '
      BEGIN { ok=0; depth=0 }
      {
        for (i=1; i<=length($0); i++) {
          c=substr($0,i,1)
          if (c=="(") depth++
          else if (c==")") { depth--; if (depth==0) ok=1; if (depth<0) exit 1 }
        }
      }
      END { exit !(ok && depth==0) }
    ' || fail
    # Return type = everything after the OUTER param list's MATCHING close paren. A naive
    # `${body#*)}` (first `)`) is WRONG when a parameter carries an inline arrow-function type
    # like `fn: (tx: Db) => Promise<T>`: the first `)` closes the arrow-fn's own params, not
    # the outer list, corrupting the return type. Paren-BALANCE from the first `(` (params are
    # wildcarded as $$$ in the pattern, so only the return type must be extracted correctly).
    ret=$(printf '%s' "$body" | awk '{
      depth=0; retstart=0; n=length($0);
      for (i=1; i<=n; i++) { c=substr($0,i,1);
        if (c=="(") { depth++ }
        else if (c==")") { depth--; if (depth==0) { retstart=i+1; break } } }
      if (retstart>0) print substr($0, retstart) }')
    ret=$(trim "$ret")
    case "$ret" in
      "") ;;
      ":"*) ;;
      *) fail ;;
    esac
    if [ -n "$ret" ]; then printf 'function %s($$$) %s { $$$ }' "$name" "$ret"
    else printf 'function %s($$$) { $$$ }' "$name"; fi ;;
  "const "*)
    body=$(trim "${sig#const }"); name=${body%%[ :=]*}
    [ -n "$name" ] && printf '%s' "$body" | grep -Eq '[:=]' || fail
    case "$body" in
      *=*)
        lhs=${body%%=*}
        case "$lhs" in
          *:*) printf 'const %s: $$$ = $$$' "$name" ;;
          *) printf 'const %s = $$$' "$name" ;;
        esac ;;
      *:*) printf 'const %s: $$$' "$name" ;;
      *)   printf 'const %s' "$name" ;;
    esac ;;
  "class "*)
    body=$(trim "${sig#class }"); name=${body%%[ {<]*}
    [ -n "$name" ] && printf '%s' "$body" | grep -Eq '\{.*\};?[[:space:]]*$' || fail
    case "$body" in
      *" extends "*) printf 'class %s extends $BASE { $$$ }' "$name" ;;
      *) printf 'class %s { $$$ }' "$name" ;;
    esac ;;
  *)
    fail ;;
esac
