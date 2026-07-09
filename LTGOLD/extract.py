encoding = "cp866"

def contains_cyrillic(s):
    return any('А' <= c <= 'я' or c in 'ёЁ' for c in s)

path = "LTGOLD.EXE"
f = open(path, "rb")
data = f.read()

# Разбиваем по нулевому байту
blocks = data.split(b'\x00')
for block in blocks:
		try:
				# Декодируем блок как cp866
				text = block.decode(encoding)
				# Заменяем 0x20 на обычный пробел
				text = text.replace('\xa0', ' ')  # в CP866 0xA0 это часто неразрывный пробел
				if contains_cyrillic(text):
						print(text)
		except UnicodeDecodeError:
				continue
