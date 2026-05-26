#!/usr/bin/env bash
# Test OSC8 hyperlinks in the terminal
# Format: \e]8;PARAMS;URI\aLABEL\e]8;;\a
#   PARAMS is empty for no params, "id=FOO" for an explicit OSC 8 id.

link() {
  local uri="$1" label="$2"
  printf '\e]8;;%s\a%s\e]8;;\a' "$uri" "$label"
}

link_id() {
  local id="$1" uri="$2" label="$3"
  printf '\e]8;id=%s;%s\a%s\e]8;;\a' "$id" "$uri" "$label"
}

echo "Plain text (no link)"
echo -n "Basic link: "
link "https://example.com" "Example"
echo ""
echo ""
echo -n "Email link: "
link "mailto:test@example.com" "Email"
echo ""
echo ""
echo -n "File link: "
link "file:///etc/hosts" "/etc/hosts"
echo ""
echo ""
echo "Multiple links on one line:"
echo -n "  "; link "https://emacs.org" "Emacs"; echo -n "  "; link "https://github.com" "GitHub"; echo ""
echo ""
echo "Link with special chars:"
echo -n "  "; link "https://example.com/path?foo=bar&baz=qux" "Query params"
echo ""
echo ""

# --- OSC 8 id-based dedup -----------------------------------------------
# These exercise `ghostel-next-hyperlink' / `ghostel-previous-hyperlink'
# (C-c C-n / C-c C-p).  With OSC 8 id dedup, chunks that share the same
# id=... parameter are visited only once.  Chunks emitted without an id
# get distinct implicit ids and are visited individually.

echo "OSC 8 id dedup — try C-c C-n / C-c C-p over the next blocks:"
echo ""

echo "1) Wrapped URL with shared id=wrap (should stop ONCE on the whole link):"
echo -n "   "
link_id "wrap" "https://wrapped.example" "http://exa"
echo ""
echo -n "           middle text "
echo ""
echo -n "   "
link_id "wrap" "https://wrapped.example" "mple.com"
echo ""
echo ""

echo "2) Imaginary text editor box (verbatim from the issue):"
echo "   Both halves of http://example.com share id=ed1."
cat <<EOF
   ╔═ file1 ════╗
   ║          ╔═ file2 ═══╗
   ║$(link_id ed1 'http://example.com' 'http://exa')║Lorem ipsum║
   ║$(link_id ed1 'http://example.com' 'le.com    ')║ dolor sit ║
   ║          ║amet, conse║
   ╚══════════║ctetur adip║
              ╚═══════════╝
EOF
echo ""

echo "3) Same URL, DIFFERENT explicit ids (should stop on EACH — they are"
echo "   semantically distinct links):"
echo -n "   "
link_id "a" "https://example.com" "first"
echo -n " ... "
link_id "b" "https://example.com" "second"
echo ""
echo ""

echo "4) Two OSC 8 sequences with NO id at all (each gets a fresh implicit"
echo "   counter — should stop on each):"
echo -n "   "
link "https://implicit.example" "alpha"
echo -n " ... "
link "https://implicit.example" "beta"
echo ""
echo ""

echo "5) Single OSC 8 begin/end spanning multiple visual rows via wrap"
echo "   (one logical region, no id needed — Emacs treats each row as a"
echo "   separate help-echo run, so dedup falls back to the old behavior"
echo "   of stopping on each row):"
printf '   \e]8;;https://example.com/long\a'
printf 'Cursor movement within the same OSC 8 run: move   right'
printf '\e]8;;\a\n'
echo ""

echo "6) Common case: long URL wrapped in a rounded box (as Claude Code,"
echo "   gh, etc. render plan/output panels).  Both halves share id=box1"
echo "   so C-c C-n should stop on the URL exactly once:"
cat <<EOF
   ╭───────────────────────────────────────────────────────────╮
   │ See $(link_id box1 'https://github.com/dakra/ghostel/blob/main/lisp/ghostel.el' 'https://github.com/dakra/ghostel/blob/main/lisp/ghos')  │
   │ $(link_id box1 'https://github.com/dakra/ghostel/blob/main/lisp/ghostel.el' 'tel.el') for the source.                                    │
   ╰───────────────────────────────────────────────────────────╯
EOF
echo ""
