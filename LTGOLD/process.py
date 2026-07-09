import os

target = "перспективный".encode("cp866")
folder = "."
# folder = "/Users/igor/Downloads/SAR2BI"
# folder = "/Users/igor/Downloads/STYLUS/STYLUS"
# /Users/igor/Desktop/SAR2BI

context = 5  # bytes before/after

for root, dirs, files in os.walk(folder):
    for name in files:
        path = os.path.join(root, name)

        try:
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            continue

        pos = 0

        while True:
            idx = data.find(target, pos)
            if idx == -1:
                break

            start = max(0, idx - context)
            end = min(len(data), idx + len(target) + context)
            snippet_bytes = data[start:end]

            # decode cp866 → unicode; errors replaced
            snippet_text = snippet_bytes.decode("cp866", errors="replace")

            print(f"{path}: {snippet_text}")

            pos = idx + 1
