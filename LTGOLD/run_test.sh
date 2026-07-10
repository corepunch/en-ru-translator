#!/bin/sh
# run_test.sh — Run an LTPRO EXE on a test sentence via DOSBox-X (headless)
#
# Usage:
#   ./run_test.sh "Sentence."
#   ./run_test.sh "Sentence." LTPRO_NO_T1.EXE
#
# The EXE must be in the same directory as this script (needs BASE.DIC etc).
# Output: UTF-8 translated text to stdout.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SENTENCE="${1:-He was arrested by the police last year.}"
EXE="${2:-LTPRO.EXE}"

printf "%s\r\n" "$SENTENCE" > "$SCRIPT_DIR/IN.TXT"
rm -f "$SCRIPT_DIR/OUT.TXT"

CFG="$SCRIPT_DIR/_dosbox_run.conf"
cat > "$CFG" << EOF
[cpu]
core=auto
cycles=max
[midi]
mididevice=none
[sblaster]
sbtype=none
[gus]
gus=false
[speaker]
pcspeaker=false
[joystick]
joysticktype=none
[autoexec]
mount c $SCRIPT_DIR
c:
$EXE IN.TXT OUT.TXT -F-
exit
EOF

dosbox-x -conf "$CFG" -silent 2>/dev/null
rm -f "$CFG"

if [ -f "$SCRIPT_DIR/OUT.TXT" ] && [ -s "$SCRIPT_DIR/OUT.TXT" ]; then
  python3 -c "print(open('$SCRIPT_DIR/OUT.TXT','rb').read().decode('cp866','replace').strip())"
else
  echo "ERROR: $EXE produced no output" >&2
  exit 1
fi
