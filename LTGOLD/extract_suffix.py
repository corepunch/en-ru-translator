#!/usr/bin/env python3
"""Extract the LTGOLD English suffix analyzer table as Lua data."""

import struct
from pathlib import Path


DATA = Path(__file__).with_name("LTGOLD.dat")
TABLE_OFFSET = 2136
RECORD_SIZE = 10


def cstring(data, offset):
    end = data.index(0, offset)
    return data[offset:end].decode("cp866")


def main():
    data = DATA.read_bytes()
    print("-- Extracted from LTGOLD.dat offset 2136 by LTGOLD/extract_suffix.py.")
    print("return {")
    offset = TABLE_OFFSET
    while offset + RECORD_SIZE <= len(data):
        flag, suffix_offset, _, tag_offset, _ = struct.unpack_from("<HHHHH", data, offset)
        if flag == suffix_offset == tag_offset == 0:
            break
        suffix = cstring(data, suffix_offset).replace('"', '\\"')
        tag = cstring(data, tag_offset).replace('"', '\\"')
        print(f'  {{ flag = 0x{flag:02X}, suffix = "{suffix}", tag = "{tag}" }},')
        offset += RECORD_SIZE
    print("}")


if __name__ == "__main__":
    main()
