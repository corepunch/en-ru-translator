#!/usr/bin/env python3
"""Inspect and edit LTech DIC 2.00 dictionaries, and read Сократ LTS dictionaries.

LTGOLD ``*.DIC`` and ``*.RUS`` files are ``LTech DIC File 2.00`` images.
Each record is one CP866 line, ``headword*code``, between a fixed header and
a two-letter index. Сократ (SOKRAT) ships the same kind of text as
``LTS Dictionary (C) 1993-1995 Sarma Ltd.`` images, often SZDD-compressed.
The index is rebuilt on every write. LTech fills an empty doubled-letter
slot and an empty non-letter slot with the first headword of that letter.
LTS fills only the empty non-letter slot. Both rules were checked against
the shipped images.

Publish a dictionary with the commercial headwords removed::

    python3 tools/ltech_dict.py subtract LTGOLD \\
        --drop LTGOLD/Сократ --drop /path/to/SOKRAT \\
        --output publish/dicts

``subtract`` writes new files. It does not change the input unless
``--in-place`` is set.
"""

import re
import argparse
import bisect
import struct
import sys
from pathlib import Path


LTECH_MAGIC = b'LTech DIC File 2.00 '
LTS_MAGIC = b'LTS Dictionary'
SZDD_MAGIC = b'SZDD\x88\xf0\'3'
LATIN = bytes(range(ord('a'), ord('z') + 1))
CYRILLIC = bytes([0xA0 + i for i in range(16)] + [0xE0 + i for i in range(16)])
EMPTY = 0xFFFFFFFF
GENDERS = ('neuter', 'masculine', 'feminine')


class DictError(ValueError):
    """A dictionary image cannot be read or written."""


def fold_byte(value):
    if 65 <= value <= 90:
        return value + 32
    if 0x80 <= value <= 0x8F:
        return value - 0x80 + 0xA0
    if 0x90 <= value <= 0x9F:
        return value - 0x90 + 0xE0
    if value == 0xF0:
        return 0xF1
    return value


_FOLD_TABLE = bytes(fold_byte(value) for value in range(256))


def fold_key(key):
    return key.translate(_FOLD_TABLE)


def encode_cp866(text):
    try:
        return text.encode('cp866')
    except UnicodeEncodeError as exc:
        raise DictError(f'{text!r} cannot be encoded in CP866') from exc


def decode_cp866(data):
    return data.decode('cp866', 'replace')


def line_parts(line):
    star = line.rfind(b'*$')
    if star < 0:
        star = line.find(b'*')
    if star < 0:
        return line, None
    return line[:star], line[star + 1:]


def hex_bytes(text):
    compact = text.replace(' ', '').replace(',', '')
    if not compact or len(compact) % 2 or any(c not in '0123456789abcdefABCDEF' for c in compact):
        raise DictError(f'invalid hex code {text!r}')
    return bytes.fromhex(compact)


def szdd_decompress(data):
    """Decompress a Microsoft COMPRESS.EXE SZDD image.

    The ring is primed with spaces and the write position starts 16 bytes
    before the end, which is the layout COMPRESS.EXE uses. Flag bits are
    tested from the low bit. A match stores the length in the low nibble.
    """
    if not data.startswith(SZDD_MAGIC) or len(data) < 14 or data[8] != 0x41:
        raise DictError('not an SZDD compressed dictionary')
    size = struct.unpack_from('<I', data, 10)[0]
    src = data[14:]
    window = bytearray(b' ' * 4096)
    pos = 4096 - 16
    out = bytearray()
    index = 0
    while len(out) < size:
        if index >= len(src):
            break
        control = src[index]
        index += 1
        bit = 1
        while bit & 0xFF and len(out) < size:
            if index >= len(src):
                break
            if control & bit:
                byte = src[index]
                index += 1
                window[pos] = byte
                out.append(byte)
                pos = (pos + 1) & 4095
            else:
                if index + 1 >= len(src):
                    break
                match_pos = src[index]
                match_len = src[index + 1]
                index += 2
                match_pos = (match_pos | ((match_len & 0xF0) << 4)) & 4095
                match_len = (match_len & 0x0F) + 3
                for _ in range(match_len):
                    if len(out) >= size:
                        break
                    byte = window[match_pos]
                    window[pos] = byte
                    out.append(byte)
                    pos = (pos + 1) & 4095
                    match_pos = (match_pos + 1) & 4095
            bit <<= 1
    if len(out) != size:
        raise DictError(f'SZDD decompressed {len(out)} bytes, header says {size}')
    return bytes(out)


def describe_code(value):
    """Describe a BASE.RUS morphology code. Text dictionaries should not use this."""
    if not value:
        return ''
    tag = chr(value[0]) if 32 <= value[0] < 127 else f'{value[0]:02X}'
    rest = value[1:]
    detail = ''
    if tag == 'N' and len(rest) >= 3:
        gender = ((rest[1] >> 1) & 1) * 2 + (rest[1] & 1)
        detail = f' {GENDERS[gender]} paradigm {rest[2] & 0x7F}'
        if len(value) > 4:
            detail += f' stem {decode_cp866(value[4:])}'
    elif tag == 'A' and len(rest) >= 2:
        paradigm = rest[2] if (rest[0] & 1 and len(rest) >= 3) else rest[1]
        detail = f' paradigm {paradigm & 0x7F}'
    elif tag == 'V' and len(rest) >= 3:
        detail = f' paradigm {rest[2] & 0x7F}'
        if len(value) > 4:
            detail += f' stem {decode_cp866(value[4:])}'
    hexpart = rest.hex(' ').upper()
    return f'{tag}{detail} [{hexpart}]' if hexpart else tag


class Dictionary:
    def __init__(self, header, lines, leading_newlines, trailing_newlines, kind, buckets,
                 alphabet, index_style, binary_codes, end_off, size_off, stored_index,
                 source=None, framing_note=None):
        self.header = header
        self.lines = lines
        self.leading_newlines = leading_newlines
        self.trailing_newlines = trailing_newlines
        self.kind = kind
        self.buckets = buckets
        self.alphabet = alphabet
        self.index_style = index_style
        self.binary_codes = binary_codes
        self.end_off = end_off
        self.size_off = size_off
        self.stored_index = stored_index
        self.source = source
        self.framing_note = framing_note

    @property
    def index_size(self):
        return self.buckets * (self.buckets + 1) * 4

    def body(self):
        parts = [b''] * self.leading_newlines + list(self.lines) + [b''] * self.trailing_newlines
        return b'\n'.join(parts)

    def entries(self):
        for line in self.lines:
            if line:
                yield line_parts(line)

    def folded_keys(self):
        found = set()
        for key, _value in self.entries():
            if key:
                found.add(fold_key(key))
        return found

    def index_bytes(self, body=None):
        body = self.body() if body is None else body
        header_len = len(self.header)
        cols = self.buckets + 1
        alpha = set(self.alphabet)
        slots = [EMPTY] * (self.buckets * cols)
        first = {}
        index = 0
        while index < len(body):
            if body[index] != 10:
                index += 1
                continue
            end = body.find(b'\n', index + 1)
            if end < 0:
                end = len(body)
            line = body[index + 1:end]
            if line:
                key, _value = line_parts(line)
                key = fold_key(key)
                if key and key[0] in alpha:
                    row = self.alphabet.index(key[0])
                    if len(key) >= 2 and key[1] in alpha:
                        col = self.alphabet.index(key[1])
                    else:
                        col = self.buckets
                    slot = row * cols + col
                    offset = header_len + index
                    if slots[slot] == EMPTY:
                        slots[slot] = offset
                    first.setdefault(row, offset)
            index = end
        for row, offset in first.items():
            if self.index_style == 'ltech' and slots[row * cols + row] == EMPTY:
                slots[row * cols + row] = offset
            if slots[row * cols + self.buckets] == EMPTY:
                slots[row * cols + self.buckets] = offset
        return struct.pack('<' + 'I' * len(slots), *slots)

    def index_valid(self):
        if self.framing_note:
            return False
        return self.index_bytes() == self.stored_index

    def to_bytes(self):
        body = self.body()
        header = bytearray(self.header)
        body_end = len(header) + len(body)
        struct.pack_into('<I', header, self.end_off, body_end)
        struct.pack_into('<I', header, self.size_off, body_end + self.index_size)
        return bytes(header) + body + self.index_bytes(body)

    def save(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        data = self.to_bytes()
        temporary = path.with_suffix(path.suffix + '.tmp')
        temporary.write_bytes(data)
        temporary.replace(path)
        return data

    def find(self, text, partial=False):
        wanted = fold_key(encode_cp866(text))
        hits = []
        for line in self.lines:
            key, value = line_parts(line)
            folded = fold_key(key)
            if (partial and wanted in folded) or (not partial and folded == wanted):
                hits.append((key, value, line))
        return hits

    def delete_folded(self, folded_keys):
        kept = []
        removed = 0
        for line in self.lines:
            key, _value = line_parts(line)
            if key and fold_key(key) in folded_keys:
                removed += 1
            else:
                kept.append(line)
        self.lines = kept
        return removed

    def add_line(self, key, value, replace=False):
        return self.add_lines([(key, value)], replace)[0]

    def add_lines(self, pairs, replace=False):
        """Insert records before the first greater folded key, in one pass.

        Keys within one batch must be distinct. Existing records for a key are
        an error, or are removed first when ``replace`` is set.
        """
        folded = []
        for key, value in pairs:
            if (b'*' in key and not value.startswith(b'$')) or b'\n' in key or b'\n' in value:
                raise DictError('headword and code must be single lines; "*" in a pattern requires a $ action')
            folded.append(fold_key(key))
        existing = {fold_key(key) for key, _value in self.entries()}
        present = [(key, f) for (key, _value), f in zip(pairs, folded) if f in existing]
        if present and not replace:
            raise DictError(f'headword already exists: {decode_cp866(present[0][0])}')
        if present:
            self.delete_folded({f for _key, f in present})
        keys = [fold_key(line_parts(line)[0]) for line in self.lines]
        ordered = all(keys[i] <= keys[i + 1] for i in range(len(keys) - 1))
        added = []
        for (key, value), f in zip(pairs, folded):
            fresh = key + b'*' + value
            if ordered:
                position = bisect.bisect_right(keys, f)
            else:
                position = next((i for i, current in enumerate(keys) if current > f), len(keys))
            self.lines.insert(position, fresh)
            keys.insert(position, f)
            added.append(fresh)
        return added


def _frame(body):
    if body == b'':
        return 0, 0, []
    parts = body.split(b'\n')
    lead = 0
    while lead < len(parts) and parts[lead] == b'':
        lead += 1
    trail = 0
    while trail < len(parts) - lead and parts[-1 - trail] == b'':
        trail += 1
    end = len(parts) - trail if trail else len(parts)
    return lead, trail, parts[lead:end]


def _alphabet(buckets):
    if buckets == 26:
        return LATIN
    if buckets == 32:
        return CYRILLIC
    raise DictError(f'unsupported alphabet size {buckets}')


def _load_structured(data, source):
    if data.startswith(LTECH_MAGIC):
        kind = 'ltech'
        header_len, buckets_off, end_off, size_off = 0x28, 0x1C, 0x1E, 0x22
        index_style = 'ltech'
        binary_codes = data[0x15:0x17] == b'R\x00'
    elif data.startswith(LTS_MAGIC):
        kind = 'lts'
        header_len, buckets_off, end_off, size_off = 0x7C, 0x68, 0x6A, 0x6E
        index_style = 'lts'
        binary_codes = len(data) > 0x32 and data[0x30:0x32] == b'R\x00'
    else:
        raise DictError('not an LTech or LTS dictionary')
    if len(data) < header_len + 4:
        raise DictError('dictionary is shorter than its header')
    buckets = struct.unpack_from('<H', data, buckets_off)[0]
    alphabet = _alphabet(buckets)
    index_size = buckets * (buckets + 1) * 4
    claimed_end = struct.unpack_from('<I', data, end_off)[0]
    claimed_size = struct.unpack_from('<I', data, size_off)[0]
    note = None
    consistent = (claimed_size == len(data) and header_len <= claimed_end <= len(data)
                  and claimed_end + index_size == len(data))
    if consistent:
        body = data[header_len:claimed_end]
        stored = data[claimed_end:]
    else:
        if len(data) < header_len + index_size:
            raise DictError('dictionary does not contain an index')
        body = data[header_len:len(data) - index_size]
        stored = data[len(data) - index_size:]
        note = (f'header length is {claimed_size} and body end is {claimed_end}, '
                f'but the file is {len(data)} bytes; entries were read up to the trailing index')
    lead, trail, lines = _frame(body)
    return Dictionary(data[:header_len], lines, lead, trail, kind, buckets, alphabet,
                      index_style, binary_codes, end_off, size_off, stored, source, note)


def load_dictionary_bytes(data, source=None):
    if data.startswith(SZDD_MAGIC):
        data = szdd_decompress(data)
    return _load_structured(data, source or Path('<memory>'))


def load_dictionary(path):
    path = Path(path)
    return load_dictionary_bytes(path.read_bytes(), path)


def load_plain(path):
    raw = Path(path).read_bytes()
    if raw.startswith(b'\xef\xbb\xbf'):
        raw = raw[3:]
    try:
        text = raw.decode('utf-8')
        encoded = [encode_cp866(line) for line in text.splitlines()]
    except (UnicodeDecodeError, DictError):
        encoded = raw.splitlines()
    lines = []
    for line in encoded:
        stripped = line.strip()
        if not stripped or stripped.startswith(b'#'):
            continue
        lines.append(stripped)
    if not lines:
        raise DictError('no dictionary lines found')
    return lines


def iter_key_sources(path, verbose=False, exclude=()):
    """Yield ``(path, folded headwords)`` from a file or a directory tree."""
    path = Path(path)
    files = [path] if path.is_file() else sorted(item for item in path.rglob('*') if item.is_file())
    explicit = path.is_file()
    excluded = {Path(item).resolve() for item in exclude}
    for item in files:
        if item.resolve() in excluded:
            continue
        try:
            head = item.read_bytes()[:64]
        except OSError as exc:
            if explicit:
                raise DictError(str(exc)) from exc
            continue
        recognized = (head.startswith(SZDD_MAGIC) or head.startswith(LTECH_MAGIC)
                      or head.startswith(LTS_MAGIC))
        try:
            if head.startswith(SZDD_MAGIC):
                payload = szdd_decompress(item.read_bytes())
                if payload.startswith(LTECH_MAGIC) or payload.startswith(LTS_MAGIC):
                    # Parse the decompressed image without writing it back.
                    dictionary = _load_structured(payload, item)
                    yield item, dictionary.folded_keys()
                elif explicit:
                    raise DictError('SZDD payload is not a dictionary')
                elif verbose:
                    print(f'skip {item}: SZDD payload is not a dictionary', file=sys.stderr)
            elif head.startswith(LTECH_MAGIC) or head.startswith(LTS_MAGIC):
                yield item, load_dictionary(item).folded_keys()
            elif explicit:
                keys = set()
                for line in load_plain(item):
                    key, _value = line_parts(line)
                    if key:
                        keys.add(fold_key(key))
                if not keys:
                    raise DictError('no headwords found')
                yield item, keys
        except DictError as exc:
            if explicit:
                raise
            if recognized or verbose:
                print(f'skip {item}: {exc}', file=sys.stderr)


def collect_keys(paths, verbose=False, exclude=()):
    found = set()
    used = []
    for path in paths:
        for item, keys in iter_key_sources(path, verbose, exclude):
            found |= keys
            used.append((item, len(keys)))
    return found, used


def format_entry(dictionary, key, value):
    shown = decode_cp866(key)
    if value is None:
        return shown
    if dictionary.binary_codes:
        return f'{shown}  {describe_code(value)}'
    return f'{shown}*{decode_cp866(value)}'


def _targets(path):
    path = Path(path)
    if path.is_file():
        return [path]
    if not path.is_dir():
        raise DictError(f'no such file or directory: {path}')
    found = []
    for item in sorted(path.iterdir()):
        if not item.is_file():
            continue
        head = item.read_bytes()[:len(LTECH_MAGIC)]
        if head.startswith(LTECH_MAGIC) or head.startswith(LTS_MAGIC):
            found.append(item)
    if not found:
        raise DictError(f'no LTech or LTS dictionaries in {path}')
    return found


def _write_result(dictionary, destination, in_place):
    if in_place:
        dictionary.save(dictionary.source)
        return dictionary.source
    if destination is None:
        raise DictError('pass --output or --in-place')
    destination = Path(destination)
    if destination.exists() and destination.is_dir():
        destination = destination / Path(dictionary.source).name
    dictionary.save(destination)
    return destination


def command_info(dictionary, _args):
    language = decode_cp866(dictionary.header[0x15:0x18]).replace('\x00', '')
    if dictionary.kind == 'lts':
        language = decode_cp866(dictionary.header[0x30:0x32]).replace('\x00', '')
    alphabet = 'Latin' if dictionary.buckets == 26 else 'Cyrillic'
    print(f'file: {dictionary.source}')
    print(f'format: {dictionary.kind}')
    print(f'language: {language}')
    print(f'alphabet: {alphabet} ({dictionary.buckets})')
    print(f'entries: {sum(1 for _key, _value in dictionary.entries())}')
    print(f'lines: {len(dictionary.lines)}')
    print(f'index: {"valid" if dictionary.index_valid() else "stale"} '
          f'({dictionary.buckets} x {dictionary.buckets + 1})')
    if dictionary.framing_note:
        print(f'warning: {dictionary.framing_note}')


def command_list(dictionary, args):
    shown = 0
    skipped = 0
    needle = fold_key(encode_cp866(args.contains)) if args.contains else None
    for key, value in dictionary.entries():
        if needle is not None and needle not in fold_key(key):
            continue
        if skipped < args.offset:
            skipped += 1
            continue
        print(format_entry(dictionary, key, value))
        shown += 1
        if args.limit and shown >= args.limit:
            break
    if not shown:
        print('no entries')


def command_find(dictionary, args):
    hits = dictionary.find(args.word, partial=args.partial)
    if not hits:
        print(f'no entries for {args.word!r}')
        return 1
    for key, value, _line in hits:
        print(format_entry(dictionary, key, value))
    return 0


def command_check(dictionary, _args):
    command_info(dictionary, _args)
    return 0 if dictionary.index_valid() else 1


def command_export(dictionary, args):
    rows = []
    for key, value in dictionary.entries():
        if dictionary.binary_codes:
            code = '' if value is None else value.hex(' ').upper()
            rows.append(f'{decode_cp866(key)}\t{code}')
        else:
            rows.append(format_entry(dictionary, key, value))
    text = '\n'.join(rows) + ('\n' if rows else '')
    if args.output:
        Path(args.output).write_text(text, encoding='utf-8')
        print(f'wrote {len(rows)} entries to {args.output}')
    else:
        sys.stdout.write(text)


def _value_from_args(args):
    if args.hex and args.value:
        raise DictError('pass only one of --value and --hex')
    if args.hex:
        return hex_bytes(args.hex)
    if args.value is None:
        raise DictError('pass --value or --hex')
    return encode_cp866(args.value)


def command_add(dictionary, args):
    key = encode_cp866(args.key)
    dictionary.add_line(key, _value_from_args(args), replace=args.replace)
    destination = _write_result(dictionary, args.output, args.in_place)
    print(f'added {args.key} -> {destination} ({sum(1 for _k, _v in dictionary.entries())} entries)')


def rus_code(text):
    """A .RUS code written as text: the class letter, its code bytes in hex,
    then any trailing lemma (a verb's perfective partner): `N 80 80 80`,
    `V C0 88 80 00 сделать`."""
    parts = text.split()
    if not parts or len(parts[0]) != 1:
        raise DictError(f'expected a class letter and hex bytes: {text!r}')
    value = bytearray(encode_cp866(parts[0]))
    rest = parts[1:]
    while rest and re.fullmatch(r'[0-9A-Fa-f]{2}', rest[0]):
        value.append(int(rest.pop(0), 16))
    if rest:
        value += encode_cp866(' '.join(rest))
    return bytes(value)


def command_import(dictionary, args):
    russian = dictionary.binary_codes or dictionary.buckets == 32
    seen = set()
    pairs = []
    removed = set()
    for number, line in enumerate(args.entries.read_text(encoding='utf-8').splitlines(), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        # Diff-like entries: "-headword" removes that headword's records,
        # "+headword*code" or plain "headword*code" adds or replaces one.
        if line.startswith('-'):
            folded = fold_key(encode_cp866(line[1:]))
            if not folded or folded in removed:
                raise DictError(f'{args.entries}:{number}: expected one -headword per line')
            removed.add(folded)
            continue
        if line.startswith('+'):
            line = line[1:]
        if russian:
            head, star, code = line.partition('*')
            if not star:
                raise DictError(f'{args.entries}:{number}: expected lemma*class hex...')
            key, value = encode_cp866(head), rus_code(code)
        else:
            key, value = line_parts(encode_cp866(line))
        if not key or not value:
            raise DictError(f'{args.entries}:{number}: expected nonempty headword*code')
        folded = fold_key(key)
        if folded in seen:
            raise DictError(f'{args.entries}:{number}: duplicate headword {decode_cp866(key)!r}')
        seen.add(folded)
        pairs.append((key, value))
    count = len(pairs)
    if not count and not removed:
        raise DictError(f'{args.entries}: no entries to import')
    if removed & seen:
        raise DictError(f'{args.entries}: a headword is both removed and added')
    present = {fold_key(key) for key, _value in dictionary.entries()}
    missing = sorted(decode_cp866(key) for key in removed - present)
    if missing:
        raise DictError(f'{args.entries}: removed headwords not in the dictionary: {", ".join(missing)}')
    deleted = dictionary.delete_folded(removed) if removed else 0
    dictionary.add_lines(pairs, replace=args.replace)
    destination = _write_result(dictionary, args.output, args.in_place)
    print(f'imported {count} entries, removed {deleted} -> {destination}')


def command_delete(dictionary, args):
    if not args.key and not args.keys_file and not args.contains:
        raise DictError('pass --key, --keys-file, or --contains')
    folded = set()
    for word in args.key or []:
        folded.add(fold_key(encode_cp866(word)))
    if args.keys_file:
        folded |= next(keys for _path, keys in iter_key_sources(args.keys_file))
    if args.contains:
        needle = fold_key(encode_cp866(args.contains))
        for key, _value in dictionary.entries():
            if needle in fold_key(key):
                folded.add(fold_key(key))
    removed = dictionary.delete_folded(folded)
    destination = _write_result(dictionary, args.output, args.in_place)
    print(f'removed {removed} -> {destination} ({sum(1 for _k, _v in dictionary.entries())} entries)')


def command_rebuild(dictionary, args):
    destination = _write_result(dictionary, args.output, args.in_place)
    print(f'rebuilt {destination}: {sum(1 for _k, _v in dictionary.entries())} entries')


def command_overlap(args):
    targets = _targets(args.target)
    drops = [Path(path) for path in args.drop]
    print(f'drop sources: {len(drops)}')
    for target in targets:
        dictionary = load_dictionary(target)
        banned, used = collect_keys(drops, args.verbose, exclude=[target])
        own = dictionary.folded_keys()
        removed = own & banned
        print(f'{target}: {len(own)} headwords, {len(removed)} also in the drop sources, '
              f'{len(own - banned)} kept')
        if args.verbose:
            for item, count in used:
                print(f'  source {item}: {count} headwords')
        if args.show:
            for key, _value in dictionary.entries():
                if fold_key(key) in removed:
                    print(f'  - {decode_cp866(key)}')


def command_subtract(args):
    targets = _targets(args.target)
    if len(targets) > 1 and args.in_place:
        raise DictError('--in-place applies to one dictionary; pass --output for a directory')
    if len(targets) > 1 and not args.output:
        raise DictError('pass --output directory when the target is a directory')
    output = Path(args.output) if args.output else None
    if len(targets) > 1:
        output.mkdir(parents=True, exist_ok=True)
    for target in targets:
        dictionary = load_dictionary(target)
        banned, used = collect_keys(args.drop, args.verbose, exclude=[target])
        before = sum(1 for _key, _value in dictionary.entries())
        removed = dictionary.delete_folded(banned)
        if args.dry_run:
            print(f'{target}: would remove {removed} of {before}')
            if args.verbose:
                for item, count in used:
                    print(f'  source {item}: {count} headwords')
            continue
        if len(targets) == 1:
            destination = _write_result(dictionary, output, args.in_place)
        else:
            destination = output / target.name
            dictionary.save(destination)
        print(f'{target.name}: removed {removed} of {before}, kept {before - removed} -> {destination}')


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)

    def add_dictionary(command):
        command.add_argument('dictionary', type=Path)

    def add_write(command):
        command.add_argument('--output', '-o', type=Path, help='write the edited dictionary here')
        command.add_argument('--in-place', action='store_true', help='replace the input file')

    info = sub.add_parser('info', help='show the header, entry count, and index status')
    add_dictionary(info)
    listing = sub.add_parser('list', help='print entries')
    add_dictionary(listing)
    listing.add_argument('--contains', help='keep entries whose headword contains this text')
    listing.add_argument('--offset', type=int, default=0)
    listing.add_argument('--limit', type=int, default=50, help='maximum entries to print; 0 prints every match')
    find = sub.add_parser('find', help='find a headword')
    add_dictionary(find)
    find.add_argument('word')
    find.add_argument('--partial', action='store_true')
    check = sub.add_parser('check', help='report whether the index matches the entries')
    add_dictionary(check)
    export = sub.add_parser('export', help='write UTF-8 text; morphology codes are hex')
    add_dictionary(export)
    export.add_argument('--output', '-o', type=Path)
    add = sub.add_parser('add', help='insert or replace one entry and rebuild the index')
    add_dictionary(add)
    add.add_argument('--key', required=True)
    add.add_argument('--value', help='code text after "*", encoded as CP866')
    add.add_argument('--hex', help='raw code bytes after "*", hex, including the tag byte')
    add.add_argument('--replace', action='store_true', help='replace an existing headword')
    add_write(add)
    entry_import = sub.add_parser('import', help='import UTF-8 headword*code lines and rebuild the index')
    add_dictionary(entry_import)
    entry_import.add_argument('--entries', required=True, type=Path, help='UTF-8 entry file; blank lines are ignored')
    entry_import.add_argument('--replace', action='store_true', help='replace existing headwords')
    add_write(entry_import)
    delete = sub.add_parser('delete', help='remove entries and rebuild the index')
    add_dictionary(delete)
    delete.add_argument('--key', action='append', default=[], help='exact headword; repeat for several')
    delete.add_argument('--keys-file', type=Path, help='dictionary or headword list to remove')
    delete.add_argument('--contains', help='remove headwords that contain this text')
    add_write(delete)
    rebuild = sub.add_parser('rebuild', help='rewrite a dictionary with a fresh index')
    add_dictionary(rebuild)
    add_write(rebuild)
    overlap = sub.add_parser('overlap', help='count headwords shared with drop sources')
    overlap.add_argument('target', type=Path, help='dictionary file or directory of dictionaries')
    overlap.add_argument('--drop', required=True, action='append', type=Path,
                         help='Сократ tree, dictionary, or headword list; repeat to add sources')
    overlap.add_argument('--show', action='store_true', help='print every shared headword')
    overlap.add_argument('--verbose', '-v', action='store_true')
    subtract = sub.add_parser('subtract', help='write dictionaries with drop-source headwords removed')
    subtract.add_argument('target', type=Path, help='dictionary file or directory of LTech/LTS dictionaries')
    subtract.add_argument('--drop', required=True, action='append', type=Path,
                          help='Сократ tree, dictionary, or headword list; repeat to add sources')
    subtract.add_argument('--output', '-o', type=Path, help='output file, or directory when the target is a directory')
    subtract.add_argument('--in-place', action='store_true')
    subtract.add_argument('--dry-run', action='store_true')
    subtract.add_argument('--verbose', '-v', action='store_true')
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == 'overlap':
            command_overlap(args)
            return 0
        if args.command == 'subtract':
            command_subtract(args)
            return 0
        dictionary = load_dictionary(args.dictionary)
        commands = {
            'info': command_info,
            'list': command_list,
            'find': command_find,
            'check': command_check,
            'export': command_export,
            'add': command_add,
            'import': command_import,
            'delete': command_delete,
            'rebuild': command_rebuild,
        }
        result = commands[args.command](dictionary, args)
        return 0 if result is None else result
    except (DictError, OSError, UnicodeError) as exc:
        print(f'ltech_dict: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
