import sys
import re

def print_long_latin_lines(filename, min_len=10):
    pattern = re.compile(r"[A-Za-z]{" + str(min_len) + r",}")

    with open(filename, "r", encoding="utf-8", errors="ignore") as f:
        for line_no, line in enumerate(f, 1):
            for match in pattern.findall(line):
                print(f"{line_no}: {match}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python script.py <filename> [min_length]")
        return

    filename = sys.argv[1]
    min_len = int(sys.argv[2]) if len(sys.argv) >= 3 else 10
    print_long_latin_lines(filename, min_len)

if __name__ == "__main__":
    main()
