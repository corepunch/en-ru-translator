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
# Per-process 8.3 names let mutation sweeps run without clobbering another DOSBox job.
INPUT_NAME="I$$.TXT"
OUTPUT_NAME="O$$.TXT"
CFG_NAME="_dosbox_run_$$.conf"
INPUT="$SCRIPT_DIR/$INPUT_NAME"
OUTPUT="$SCRIPT_DIR/$OUTPUT_NAME"
CFG="$SCRIPT_DIR/$CFG_NAME"

# Keep differential tests away from the tracked IN.TXT/OUT.TXT reference artifacts.
trap 'rm -f "$INPUT" "$OUTPUT" "$CFG"' EXIT
printf "%s\r\n" "$SENTENCE" > "$INPUT"
rm -f "$OUTPUT"

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
$EXE $INPUT_NAME $OUTPUT_NAME -F-
exit
EOF

dosbox-x -conf "$CFG" -silent 2>/dev/null
if [ -f "$OUTPUT" ] && [ -s "$OUTPUT" ]; then
  python3 -c "print(open('$OUTPUT','rb').read().decode('cp866','replace').strip())"
else
  echo "ERROR: $EXE produced no output" >&2
  exit 1
fi
