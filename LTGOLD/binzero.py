#!/usr/bin/env python3
import sys

def zero_range(filename, start, length):
    with open(filename, "r+b") as f:
        f.seek(start)
        f.write(b"\x00" * length)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <file> <start_offset> <length>")
        sys.exit(1)

    file_name = sys.argv[1]
    start_offset = int(sys.argv[2], 0)  # supports decimal or 0x...
    end_offset = int(sys.argv[3], 0)

    if start_offset < 0 or end_offset < 0:
        raise ValueError("start_offset and length must be non-negative")

    zero_range(file_name, start_offset, end_offset-start_offset)
