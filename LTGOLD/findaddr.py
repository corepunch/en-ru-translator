fst = 72
snd = 15


# 369514 364491
# 39434

# 371184
# diff: 364491-330080
# m-nouns: 356153-330080

def find_words_with_offsets(filename):
    with open(filename, "rb") as f:
        data = f.read()

    data_len = len(data)
    results = []

    for i in range(data_len - 1):  # first word
        first_word = int.from_bytes(data[i:i+2], "little")

        # check offsets 0..8 for the second word
        for offset in range(0, 9):
            second_pos = i + 2 + offset
            if second_pos + 1 >= data_len:
                continue

            second_word = int.from_bytes(data[second_pos:second_pos+2], "little")
            if second_word != first_word + fst:
                continue

            # check third word at same offset from second word
            third_pos = second_pos + 2 + offset
            if third_pos + 1 >= data_len:
                continue

            third_word = int.from_bytes(data[third_pos:third_pos+2], "little")
            if third_word == second_word + snd:
                # capture bytes between words
                between_first_second = data[i+2:second_pos]
                between_second_third = data[second_pos+2:third_pos]

                results.append({
                    "positions": (i, second_pos, third_pos),
                    "values": (first_word, second_word, third_word),
                    "bytes_between_first_second": between_first_second,
                    "bytes_between_second_third": between_second_third
                })

    return results, data_len


# Example usage
filename = "LTGOLD.EXE"
matches, file_size = find_words_with_offsets(filename)

print(f"File size: {file_size} bytes\n")

for match in matches:
    pos = match["positions"]
    val = match["values"]
    b1 = match["bytes_between_first_second"]
    b2 = match["bytes_between_second_third"]

    print(f"First word at {pos[0]} = {val[0]}")
    print(f"Second word at {pos[1]} = {val[1]}")
    print(f"Third word at {pos[2]} = {val[2]}")
    print(f"Bytes between first and second ({len(b1)} bytes): {b1.hex()}")
    print(f"Bytes between second and third ({len(b2)} bytes): {b2.hex()}\n")
