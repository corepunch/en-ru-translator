import struct

def parse_mz_and_find_data(filename):
    try:
        with open(filename, 'rb') as f:
            data = f.read(64)
            if len(data) < 10:
                print(f"File too small ({len(data)} bytes) - not EXE?")
                return
            
            e_magic, e_cblp, e_cp, e_crlc, e_cparhdr = struct.unpack('<HHHHH', data[:10])
            
            if len(data) < 28:
                e_ip, e_cs, e_lfarlc, e_ovno = 0, 0, 0, 0
            else:
                e_ip, e_cs, e_lfarlc, e_ovno = struct.unpack('<HHHH', data[20:28])
        
            print(f"MZ Magic: {e_magic:04X} (OK)")
            print(f"Header size: {e_cparhdr} paragraphs = {e_cparhdr * 16} bytes")
            print(f"Load image size: {e_cp} pages = {e_cp * 512} bytes")
            print(f"Relocs count: {e_crlc}")
            print(f"Reloc table offset: {e_lfarlc:04X}")
            print(f"Entry point: CS:{e_cs:04X} IP:{e_ip:04X}")
            
            header_end = e_cparhdr * 16
            print(f"\nLoad image (CODE + DATA) starts at offset {header_end:04X}")
            
            # Read full reloc table
            if e_crlc > 0 and e_lfarlc > 0:
                f.seek(e_lfarlc)
                relocs_data = f.read(e_crlc * 4)
                if len(relocs_data) == e_crlc * 4:
                    relocs = []
                    for i in range(e_crlc):
                        reloc = struct.unpack('<HH', relocs_data[i*4:(i+1)*4])
                        relocs.append(reloc[1])  # Only offsets (low word)
                    relocs.sort()
                    print(f"Sorted reloc offsets (first 10): {relocs[:10]}")
                    print(f"Sorted reloc offsets (last 10): {relocs[-10:]}")
                    print(f"Max reloc offset: {max(relocs):04X} — likely end of code/data")
                    # Find clusters for data (gaps > 0x100 suggest code vs data)
                    clusters = []
                    current_cluster = [relocs[0]]
                    for off in relocs[1:]:
                        if off - current_cluster[-1] > 0x100:  # Big gap = new cluster
                            clusters.append(current_cluster)
                            current_cluster = [off]
                        else:
                            current_cluster.append(off)
                    clusters.append(current_cluster)
                    print(f"Reloc clusters (possible code/data sections): {[f'{hex(min(c))}-{hex(max(c))}' for c in clusters[:3]]}...")  # First few
                else:
                    print(f"Reloc table incomplete ({len(relocs_data)}/{e_crlc*4} bytes)")
            
            # Scan load image for data-like regions (high printable + nulls)
            f.seek(header_end)
            load_size = e_cp * 512 - header_end
            if load_size > 0:
                load_data = f.read(load_size)
                # Find regions with >50% printable + frequent nulls (strings)
                window_size = 512  # Page-sized windows
                data_candidates = []
                for i in range(0, len(load_data) - window_size, 256):  # Step 256
                    window = load_data[i:i+window_size]
                    printables = sum(1 for b in window if 0x20 <= b <= 0x7E or b in [0x3C, 0x3E, 0x5B, 0x5D, 0x2A, 0x7E, 0x40, 0x24])  # <>[*~@$
                    nulls = window.count(0)
                    if printables > window_size * 0.5 and nulls > 5:  # String-like
                        offset = header_end + i
                        data_candidates.append((offset, printables, nulls))
                        print(f"Data candidate at {offset:08X}: {printables} printable, {nulls} nulls")
                if data_candidates:
                    sorted_candidates = sorted(data_candidates, key=lambda x: x[1], reverse=True)  # By printable density
                    print(f"\nTop data candidates (offsets in file): {[(hex(off), p, n) for off, p, n in sorted_candidates[:5]]}")
                    # Check user's known offset
                    user_offset = 0x507A0  # 330080 dec = 0x507A0 hex
                    matched = False
                    for off, p, n in data_candidates:
                        if abs(off - user_offset) < 0x1000:  # Near user's find (±4K)
                            print(f"✅ User's offset {user_offset:08X} matches candidate at {off:08X} (density: {p/window_size*100:.1f}%)!")
                            matched = True
                            break
                    if not matched:
                        print(f"❌ User's offset {user_offset:08X} not in top candidates — check manually (maybe low nulls).")
                else:
                    print("No strong data candidates found — scan manually in hex editor.")
            else:
                print("Load image empty — weird.")
                
    except FileNotFoundError:
        print(f"File not found: {filename}")
    except Exception as e:
        print(f"Error: {e}")

# Usage
parse_mz_and_find_data('LTGOLD.EXE')