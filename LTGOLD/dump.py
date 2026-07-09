#!/usr/bin/env python3
# cp866_dump.py

import sys, argparse

def to_enc(b, enc):
	try: ch = bytes([b]).decode(enc); return ch if ch.isprintable() else "."
	except: return "."

def dump(path, width, group, enc, show_line, show_hex, show_text):
	with open(path, "rb") as f:
		offset = 0
		while True:
			chunk = f.read(width)
			if not chunk: break

			line = []
			if show_line: line.append(f"{offset:08X}")

			if show_hex:
				hb = [f"{b:02X}" for b in chunk]
				if group > 1:
					g = [" ".join(hb[i:i+group]) for i in range(0, len(hb), group)]
					hex_part = "  ".join(g)
				else:
					hex_part = " ".join(hb)
				line.append(hex_part)

			if show_text: line.append("".join(to_enc(b, enc) for b in chunk))

			print("\t".join(line))
			offset += len(chunk)

def main():
	p = argparse.ArgumentParser(description="Hex/text dump with grouping and encoding")
	p.add_argument("file", help="binary file to dump")
	p.add_argument("--width", type=int, default=16, help="bytes per line (default: 16)")
	p.add_argument("--group", type=int, default=4, help="group bytes visually (default: 4)")
	p.add_argument("--enc", default="cp866", help="text encoding for right column (default: cp866)")
	p.add_argument("--no-line", action="store_true", help="disable line numbers")
	p.add_argument("--no-hex", action="store_true", help="disable hex output")
	p.add_argument("--no-text", action="store_true", help="disable text output")

	a = p.parse_args()
	dump(a.file, a.width, a.group, a.enc, not a.no_line, not a.no_hex, not a.no_text)

if __name__ == "__main__": main()
