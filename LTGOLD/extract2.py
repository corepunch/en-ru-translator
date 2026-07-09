import struct

FILENAME = "LTGOLD.dat"

# START,rec_size = 2136, 10
# START,rec_size = 3374, 10
# START,rec_size = 3854, 10
START,rec_size = 5434, 10
# START,rec_size = 11981, 9
# START,rec_size = 16610, 10
# START,rec_size = 16874, 10
# START,rec_size = 17972, 8
# START,rec_size = 19158, 8

def read_cstring(data, base, offset):
    """Чтение строки из общей data, но offset считается относительно base-смещения."""
    if offset == 0:
        return None
    pos = base + offset
    buf = []
    while pos < len(data) and data[pos] != 0:
        buf.append(data[pos])
        pos += 1
    return bytes(buf).decode("cp866", errors="replace")

def u16(x):
    return struct.unpack("<H", x)[0]

def u8(x: bytes) -> int:
    return struct.unpack("<B", x)[0]

def read(data, i):
    if rec_size == 10:
        # return u16(data[i:i+2]), u16(data[i+2:i+4]), u16(data[i+6:i+8]), 0
        return u16(data[i+8:i+10]), u16(data[i:i+2]), u16(data[i+4:i+6])
    elif rec_size == 9:
        return u8(data[i:i+1]), u16(data[i+1:i+3]), u16(data[i+5:i+7])
    else:
        return u16(data[i+6:i+8]), u16(data[i:i+2]), 0

def parse_records(data, base):
    i = base
    while True:
        flags,pat_off,act_off = read(data,i)
        
        # конец таблицы
        if flags == 0 and pat_off == 0 and act_off == 0:
            print('stop', i)
            break

        pattern = read_cstring(data, 0, pat_off)
        action  = read_cstring(data, 0, act_off)

        yield {
            "flags": flags,
            "pattern": pattern,
            "action": action,
        }

        i += rec_size

# ---- run ----

with open(FILENAME, "rb") as f:
    data = f.read()

records = list(parse_records(data, START))

print("return {")
for r in records:
    pat = (r["pattern"] or "").replace('"', '\\"')
    act = (r["action"] or "").replace('"', '\\"')
    print(f'  {{ "{pat}", "{act}", 0x{r["flags"]:04X} }},')
print("}")
