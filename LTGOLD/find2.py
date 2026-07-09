#!/usr/bin/env python3

import sys
import mmap

MAX_DIST = 200            # максимум байт между 2A и (7E или 60)
A = 0x2A                  # первый байт
B_SET = {0x7E, 0x60}      # второй байт (любой из этих)

def main():
    path = "LTGOLD.EXE"

    with open(path, "rb") as f:
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)

        posA = [i for i, b in enumerate(mm) if b == A]
        posB = [i for i, b in enumerate(mm) if b in B_SET]

        results = []
        for a in posA:
            for b in posB:
                if abs(a - b) <= MAX_DIST:
                    results.append((a, b))

        if not results:
            print("No matches found.")
            return

        for a, b in results:
            print(f"2A at {a:08X}, 7E/60 at {b:08X}, distance={abs(a-b)}")

        mm.close()

if __name__ == "__main__":
    main()
