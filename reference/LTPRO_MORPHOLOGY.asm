; LTPRO.EXE sha256 6a2036c2fbc629d0317bf02acbb1e6ebd82ceecb2d11f609c6460cc0c32dc4fe
; Addresses are zero-based file offsets; Capstone 16-bit x86 decoding.
; Native noun, adjective, finite verb, participle, and suffix-test helpers.

; noun
223BC  push     bp
223BD  mov      bp, sp
223BF  sub      sp, 0x10
223C2  push     si
223C3  push     di
223C4  mov      di, word ptr [bp + 0x10]
223C7  push     word ptr [bp + 0xa]
223CA  push     word ptr [bp + 8]
223CD  lcall    0, 0x3df1
223D2  pop      cx
223D3  pop      cx
223D4  mov      word ptr [bp - 0xa], ax
223D7  cmp      word ptr [bp + 0xe], 0
223DB  je       0x223e0
223DD  add      di, 6
223E0  mov      ax, word ptr [bp + 0xc]
223E3  or       ax, ax
223E5  je       0x22407
223E7  cmp      ax, 1
223EA  je       0x223f3
223EC  cmp      ax, 2
223EF  je       0x223fd
223F1  jmp      0x22411
223F3  mov      word ptr [bp - 0xc], ds
223F6  mov      word ptr [bp - 0xe], 0x5238
223FB  jmp      0x22413
223FD  mov      word ptr [bp - 0xc], ds
22400  mov      word ptr [bp - 0xe], 0x5450
22405  jmp      0x22413
22407  mov      word ptr [bp - 0xc], ds
2240A  mov      word ptr [bp - 0xe], 0x55a6
2240F  jmp      0x22413
22411  jmp      0x223f3
22413  mov      ax, word ptr [bp + 6]
22416  mov      dx, 6
22419  imul     dx
2241B  les      bx, ptr [bp - 0xe]
2241E  add      bx, ax
22420  mov      ax, word ptr [bp - 0xa]
22423  sub      ax, word ptr es:[bx]
22426  mov      si, ax
22428  or       si, si
2242A  jle      0x22447
2242C  push     si
2242D  push     word ptr [bp + 0xa]
22430  push     word ptr [bp + 8]
22433  push     ds
22434  mov      ax, 0xc858
22437  push     ax
22438  lcall    0, 0x3ecf
2243D  add      sp, 0xa
22440  mov      byte ptr [si - 0x37a8], 0
22445  jmp      0x2245a
22447  push     word ptr [bp + 0xa]
2244A  push     word ptr [bp + 8]
2244D  push     ds
2244E  mov      ax, 0xc858
22451  push     ax
22452  lcall    0, 0x3d41
22457  add      sp, 8
2245A  mov      ax, word ptr [bp + 6]
2245D  mov      dx, 6
22460  imul     dx
22462  les      bx, ptr [bp - 0xe]
22465  add      bx, ax
22467  mov      ax, word ptr es:[bx + 4]
2246B  mov      dx, word ptr es:[bx + 2]
2246F  mov      word ptr [bp - 2], ax
22472  mov      word ptr [bp - 4], dx
22475  mov      word ptr [bp - 0x10], 1
2247A  jmp      0x224a5
2247C  mov      ax, 0x20
2247F  push     ax
22480  push     word ptr [bp - 2]
22483  push     word ptr [bp - 4]
22486  lcall    0, 0x3cd4
2248B  add      sp, 6
2248E  mov      word ptr [bp - 2], dx
22491  mov      word ptr [bp - 4], ax
22494  or       ax, dx
22496  jne      0x2249f
22498  xor      dx, dx
2249A  xor      ax, ax
2249C  jmp      0x2252a
2249F  inc      word ptr [bp - 0x10]
224A2  inc      word ptr [bp - 4]
224A5  cmp      word ptr [bp - 0x10], di
224A8  jl       0x2247c
224AA  les      bx, ptr [bp - 4]
224AD  cmp      byte ptr es:[bx], 0x2d
224B1  jne      0x224b5
224B3  jmp      0x22498
224B5  les      bx, ptr [bp - 4]
224B8  cmp      byte ptr es:[bx], 0x3d
224BC  je       0x22522
224BE  or       si, si
224C0  jne      0x224c7
224C2  mov      byte ptr [si - 0x37a8], 0
224C7  mov      ax, 0x20
224CA  push     ax
224CB  push     word ptr [bp - 2]
224CE  push     word ptr [bp - 4]
224D1  lcall    0, 0x3cd4
224D6  add      sp, 6
224D9  mov      word ptr [bp - 6], dx
224DC  mov      word ptr [bp - 8], ax
224DF  mov      ax, word ptr [bp - 8]
224E2  or       ax, word ptr [bp - 6]
224E5  jne      0x224fc
224E7  push     word ptr [bp - 2]
224EA  push     word ptr [bp - 4]
224ED  push     ds
224EE  mov      ax, 0xc858
224F1  push     ax
224F2  lcall    0, 0x3c95
224F7  add      sp, 8
224FA  jmp      0x22522
224FC  mov      ax, word ptr [bp - 8]
224FF  sub      ax, word ptr [bp - 4]
22502  mov      si, ax
22504  push     si
22505  push     word ptr [bp - 2]
22508  push     word ptr [bp - 4]
2250B  push     ds
2250C  mov      ax, 0xc858
2250F  push     ax
22510  lcall    0, 0x3e34
22515  add      sp, 0xa
22518  mov      bx, word ptr [bp - 0xa]
2251B  add      bx, si
2251D  mov      byte ptr [bx - 0x37a8], 0
22522  mov      dx, ds
22524  mov      ax, 0xc858
22527  jmp      0x2249c
2252A  pop      di
2252B  pop      si
2252C  mov      sp, bp
2252E  pop      bp
2252F  retf

; adjective
22530  push     bp
22531  mov      bp, sp
22533  sub      sp, 0x10
22536  push     si
22537  push     di
22538  mov      word ptr [bp - 0xa], 0
2253D  push     word ptr [bp + 0xa]
22540  push     word ptr [bp + 8]
22543  lcall    0, 0x3df1
22548  pop      cx
22549  pop      cx
2254A  mov      di, ax
2254C  cmp      word ptr [bp + 0xe], 0
22550  je       0x22556
22552  add      word ptr [bp + 0x10], 6
22556  mov      ax, word ptr [bp + 0xc]
22559  or       ax, ax
2255B  je       0x2257d
2255D  cmp      ax, 1
22560  je       0x22569
22562  cmp      ax, 2
22565  je       0x22573
22567  jmp      0x22587
22569  mov      word ptr [bp - 0xc], ds
2256C  mov      word ptr [bp - 0xe], 0x56d4
22571  jmp      0x22589
22573  mov      word ptr [bp - 0xc], ds
22576  mov      word ptr [bp - 0xe], 0x5770
2257B  jmp      0x22589
2257D  mov      word ptr [bp - 0xc], ds
22580  mov      word ptr [bp - 0xe], 0x580c
22585  jmp      0x22589
22587  jmp      0x22569
22589  cmp      di, 2
2258C  jle      0x225d4
2258E  cmp      word ptr [bp + 6], 0xe
22592  je       0x225d4
22594  push     word ptr [0x630e]
22598  push     word ptr [0x630c]
2259C  push     di
2259D  push     word ptr [bp + 0xa]
225A0  push     word ptr [bp + 8]
225A3  lcall    0x2104, 2
225A8  add      sp, 0xa
225AB  cmp      ax, 2
225AE  je       0x225cc
225B0  push     word ptr [0x6312]
225B4  push     word ptr [0x6310]
225B8  push     di
225B9  push     word ptr [bp + 0xa]
225BC  push     word ptr [bp + 8]
225BF  lcall    0x2104, 2
225C4  add      sp, 0xa
225C7  cmp      ax, 2
225CA  jne      0x225d4
225CC  mov      word ptr [bp - 0xa], 1
225D1  sub      di, 2
225D4  mov      ax, word ptr [bp + 6]
225D7  mov      dx, 6
225DA  imul     dx
225DC  les      bx, ptr [bp - 0xe]
225DF  add      bx, ax
225E1  mov      ax, di
225E3  sub      ax, word ptr es:[bx]
225E6  mov      si, ax
225E8  or       si, si
225EA  jle      0x22607
225EC  push     si
225ED  push     word ptr [bp + 0xa]
225F0  push     word ptr [bp + 8]
225F3  push     ds
225F4  mov      ax, 0xc858
225F7  push     ax
225F8  lcall    0, 0x3ecf
225FD  add      sp, 0xa
22600  mov      byte ptr [si - 0x37a8], 0
22605  jmp      0x2261a
22607  push     word ptr [bp + 0xa]
2260A  push     word ptr [bp + 8]
2260D  push     ds
2260E  mov      ax, 0xc858
22611  push     ax
22612  lcall    0, 0x3d41
22617  add      sp, 8
2261A  mov      ax, word ptr [bp + 6]
2261D  mov      dx, 6
22620  imul     dx
22622  les      bx, ptr [bp - 0xe]
22625  add      bx, ax
22627  mov      ax, word ptr es:[bx + 4]
2262B  mov      dx, word ptr es:[bx + 2]
2262F  mov      word ptr [bp - 2], ax
22632  mov      word ptr [bp - 4], dx
22635  mov      word ptr [bp - 0x10], 0
2263A  jmp      0x22665
2263C  mov      ax, 0x20
2263F  push     ax
22640  push     word ptr [bp - 2]
22643  push     word ptr [bp - 4]
22646  lcall    0, 0x3cd4
2264B  add      sp, 6
2264E  mov      word ptr [bp - 2], dx
22651  mov      word ptr [bp - 4], ax
22654  or       ax, dx
22656  jne      0x2265f
22658  xor      dx, dx
2265A  xor      ax, ax
2265C  jmp      0x22705
2265F  inc      word ptr [bp - 0x10]
22662  inc      word ptr [bp - 4]
22665  mov      ax, word ptr [bp - 0x10]
22668  cmp      ax, word ptr [bp + 0x10]
2266B  jl       0x2263c
2266D  les      bx, ptr [bp - 4]
22670  cmp      byte ptr es:[bx], 0x2d
22674  jne      0x22678
22676  jmp      0x22658
22678  les      bx, ptr [bp - 4]
2267B  cmp      byte ptr es:[bx], 0x3d
2267F  je       0x226e2
22681  or       si, si
22683  jne      0x2268a
22685  mov      byte ptr [si - 0x37a8], 0
2268A  mov      ax, 0x20
2268D  push     ax
2268E  push     word ptr [bp - 2]
22691  push     word ptr [bp - 4]
22694  lcall    0, 0x3cd4
22699  add      sp, 6
2269C  mov      word ptr [bp - 6], dx
2269F  mov      word ptr [bp - 8], ax
226A2  mov      ax, word ptr [bp - 8]
226A5  or       ax, word ptr [bp - 6]
226A8  jne      0x226bf
226AA  push     word ptr [bp - 2]
226AD  push     word ptr [bp - 4]
226B0  push     ds
226B1  mov      ax, 0xc858
226B4  push     ax
226B5  lcall    0, 0x3c95
226BA  add      sp, 8
226BD  jmp      0x226e2
226BF  mov      ax, word ptr [bp - 8]
226C2  sub      ax, word ptr [bp - 4]
226C5  mov      si, ax
226C7  push     si
226C8  push     word ptr [bp - 2]
226CB  push     word ptr [bp - 4]
226CE  push     ds
226CF  mov      ax, 0xc858
226D2  push     ax
226D3  lcall    0, 0x3e34
226D8  add      sp, 0xa
226DB  mov      bx, si
226DD  mov      byte ptr [bx + di - 0x37a8], 0
226E2  cmp      word ptr [bp - 0xa], 0
226E6  je       0x226fd
226E8  push     word ptr [0x630e]
226EC  push     word ptr [0x630c]
226F0  push     ds
226F1  mov      ax, 0xc858
226F4  push     ax
226F5  lcall    0, 0x3c95
226FA  add      sp, 8
226FD  mov      dx, ds
226FF  mov      ax, 0xc858
22702  jmp      0x2265c
22705  pop      di
22706  pop      si
22707  mov      sp, bp
22709  pop      bp
2270A  retf

; verb
2270B  push     bp
2270C  mov      bp, sp
2270E  sub      sp, 0x12
22711  push     si
22712  push     di
22713  mov      word ptr [bp - 0xa], 0
22718  push     word ptr [bp + 0xa]
2271B  push     word ptr [bp + 8]
2271E  lcall    0, 0x3df1
22723  pop      cx
22724  pop      cx
22725  mov      si, ax
22727  mov      ax, word ptr [bp + 0xc]
2272A  or       ax, ax
2272C  je       0x22735
2272E  cmp      ax, 1
22731  je       0x2273f
22733  jmp      0x22749
22735  mov      word ptr [bp - 0xc], ds
22738  mov      word ptr [bp - 0xe], 0x5a50
2273D  jmp      0x2274b
2273F  mov      word ptr [bp - 0xc], ds
22742  mov      word ptr [bp - 0xe], 0x5e90
22747  jmp      0x2274b
22749  jmp      0x22735
2274B  test     word ptr [bp + 0xe], 4
22750  je       0x2275e
22752  mov      word ptr [bp - 0x12], 6
22757  mov      word ptr [bp + 0x14], 0
2275C  jmp      0x2279f
2275E  cmp      word ptr [bp + 0x14], 1
22762  jne      0x2276b
22764  mov      word ptr [bp - 0x12], 7
22769  jmp      0x2279f
2276B  cmp      word ptr [bp + 0x10], 0
2276F  jne      0x2278c
22771  push     word ptr [bp + 0xa]
22774  push     word ptr [bp + 8]
22777  push     ds
22778  mov      ax, 0xc858
2277B  push     ax
2277C  lcall    0, 0x3d41
22781  add      sp, 8
22784  mov      dx, ds
22786  mov      ax, 0xc858
22789  jmp      0x22a81
2278C  dec      word ptr [bp + 0x10]
2278F  mov      ax, word ptr [bp + 0x10]
22792  mov      word ptr [bp - 0x12], ax
22795  cmp      word ptr [bp + 0x12], 0
22799  je       0x2279f
2279B  add      word ptr [bp - 0x12], 3
2279F  cmp      si, 2
227A2  jle      0x227e4
227A4  push     word ptr [0x630e]
227A8  push     word ptr [0x630c]
227AC  push     si
227AD  push     word ptr [bp + 0xa]
227B0  push     word ptr [bp + 8]
227B3  lcall    0x2104, 2
227B8  add      sp, 0xa
227BB  cmp      ax, 2
227BE  je       0x227dc
227C0  push     word ptr [0x6312]
227C4  push     word ptr [0x6310]
227C8  push     si
227C9  push     word ptr [bp + 0xa]
227CC  push     word ptr [bp + 8]
227CF  lcall    0x2104, 2
227D4  add      sp, 0xa
227D7  cmp      ax, 2
227DA  jne      0x227e4
227DC  mov      word ptr [bp - 0xa], 1
227E1  sub      si, 2
227E4  mov      ax, word ptr [bp + 6]
227E7  mov      dx, 6
227EA  imul     dx
227EC  les      bx, ptr [bp - 0xe]
227EF  add      bx, ax
227F1  mov      ax, si
227F3  sub      ax, word ptr es:[bx]
227F6  mov      di, ax
227F8  or       di, di
227FA  jle      0x22817
227FC  push     di
227FD  push     word ptr [bp + 0xa]
22800  push     word ptr [bp + 8]
22803  push     ds
22804  mov      ax, 0xc858
22807  push     ax
22808  lcall    0, 0x3ecf
2280D  add      sp, 0xa
22810  mov      byte ptr [di - 0x37a8], 0
22815  jmp      0x2282a
22817  push     word ptr [bp + 0xa]
2281A  push     word ptr [bp + 8]
2281D  push     ds
2281E  mov      ax, 0xc858
22821  push     ax
22822  lcall    0, 0x3d41
22827  add      sp, 8
2282A  mov      ax, word ptr [bp + 6]
2282D  mov      dx, 6
22830  imul     dx
22832  les      bx, ptr [bp - 0xe]
22835  add      bx, ax
22837  mov      ax, word ptr es:[bx + 4]
2283B  mov      dx, word ptr es:[bx + 2]
2283F  mov      word ptr [bp - 2], ax
22842  mov      word ptr [bp - 4], dx
22845  mov      word ptr [bp - 0x10], 0
2284A  jmp      0x22870
2284C  mov      ax, 0x20
2284F  push     ax
22850  push     word ptr [bp - 2]
22853  push     word ptr [bp - 4]
22856  lcall    0, 0x3cd4
2285B  add      sp, 6
2285E  mov      word ptr [bp - 2], dx
22861  mov      word ptr [bp - 4], ax
22864  or       ax, dx
22866  jne      0x2286a
22868  jmp      0x22881
2286A  inc      word ptr [bp - 0x10]
2286D  inc      word ptr [bp - 4]
22870  mov      ax, word ptr [bp - 0x10]
22873  cmp      ax, word ptr [bp - 0x12]
22876  jl       0x2284c
22878  les      bx, ptr [bp - 4]
2287B  cmp      byte ptr es:[bx], 0x2d
2287F  jne      0x22888
22881  xor      dx, dx
22883  xor      ax, ax
22885  jmp      0x22789
22888  les      bx, ptr [bp - 4]
2288B  cmp      byte ptr es:[bx], 0x3d
2288F  je       0x228f2
22891  or       di, di
22893  jne      0x2289a
22895  mov      byte ptr [di - 0x37a8], 0
2289A  mov      ax, 0x20
2289D  push     ax
2289E  push     word ptr [bp - 2]
228A1  push     word ptr [bp - 4]
228A4  lcall    0, 0x3cd4
228A9  add      sp, 6
228AC  mov      word ptr [bp - 6], dx
228AF  mov      word ptr [bp - 8], ax
228B2  mov      ax, word ptr [bp - 8]
228B5  or       ax, word ptr [bp - 6]
228B8  jne      0x228cf
228BA  push     word ptr [bp - 2]
228BD  push     word ptr [bp - 4]
228C0  push     ds
228C1  mov      ax, 0xc858
228C4  push     ax
228C5  lcall    0, 0x3c95
228CA  add      sp, 8
228CD  jmp      0x228f2
228CF  mov      ax, word ptr [bp - 8]
228D2  sub      ax, word ptr [bp - 4]
228D5  mov      di, ax
228D7  push     di
228D8  push     word ptr [bp - 2]
228DB  push     word ptr [bp - 4]
228DE  push     ds
228DF  mov      ax, 0xc858
228E2  push     ax
228E3  lcall    0, 0x3e34
228E8  add      sp, 0xa
228EB  mov      bx, di
228ED  mov      byte ptr [bx + si - 0x37a8], 0
228F2  cmp      word ptr [bp + 0x14], 1
228F6  je       0x228fb
228F8  jmp      0x229e3
228FB  push     ds
228FC  mov      ax, 0xc858
228FF  push     ax
22900  lcall    0, 0x3df1
22905  pop      cx
22906  pop      cx
22907  mov      si, ax
22909  cmp      word ptr [bp + 0x16], 1
2290D  jne      0x22915
2290F  cmp      word ptr [bp + 0x12], 0
22913  je       0x22953
22915  push     ds
22916  mov      ax, 0xb983
22919  push     ax
2291A  push     si
2291B  push     ds
2291C  mov      ax, 0xc858
2291F  push     ax
22920  lcall    0x2104, 2
22925  add      sp, 0xa
22928  or       ax, ax
2292A  jne      0x22943
2292C  push     ds
2292D  mov      ax, 0xb987
22930  push     ax
22931  push     si
22932  push     ds
22933  mov      ax, 0xc858
22936  push     ax
22937  lcall    0x2104, 2
2293C  add      sp, 0xa
2293F  or       ax, ax
22941  je       0x22953
22943  mov      al, byte ptr [si - 0x37a9]
22947  mov      byte ptr [si - 0x37aa], al
2294B  dec      si
2294C  mov      byte ptr [si - 0x37a8], 0
22951  jmp      0x22970
22953  push     ds
22954  mov      ax, 0xb98b
22957  push     ax
22958  push     si
22959  push     ds
2295A  mov      ax, 0xc858
2295D  push     ax
2295E  lcall    0x2104, 2
22963  add      sp, 0xa
22966  or       ax, ax
22968  je       0x22970
2296A  dec      si
2296B  mov      byte ptr [si - 0x37a8], 0
22970  cmp      byte ptr [si - 0x37a9], 0xab
22975  je       0x22995
22977  cmp      word ptr [bp + 0x16], 1
2297B  jne      0x22983
2297D  cmp      word ptr [bp + 0x12], 1
22981  jne      0x22995
22983  push     ds
22984  mov      ax, 0xb98e
22987  push     ax
22988  push     ds
22989  mov      ax, 0xc858
2298C  push     ax
2298D  lcall    0, 0x3c95
22992  add      sp, 8
22995  cmp      word ptr [bp + 0x12], 0
22999  je       0x229af
2299B  push     ds
2299C  mov      ax, 0xb990
2299F  push     ax
229A0  push     ds
229A1  mov      ax, 0xc858
229A4  push     ax
229A5  lcall    0, 0x3c95
229AA  add      sp, 8
229AD  jmp      0x229e3
229AF  cmp      word ptr [bp + 0x16], 2
229B3  jne      0x229c9
229B5  push     ds
229B6  mov      ax, 0xb992
229B9  push     ax
229BA  push     ds
229BB  mov      ax, 0xc858
229BE  push     ax
229BF  lcall    0, 0x3c95
229C4  add      sp, 8
229C7  jmp      0x229e3
229C9  cmp      word ptr [bp + 0x16], 0
229CD  jne      0x229e3
229CF  push     ds
229D0  mov      ax, 0xb994
229D3  push     ax
229D4  push     ds
229D5  mov      ax, 0xc858
229D8  push     ax
229D9  lcall    0, 0x3c95
229DE  add      sp, 8
229E1  jmp      0x229e3
229E3  cmp      word ptr [bp - 0xa], 0
229E7  je       0x22a46
229E9  mov      ax, word ptr [bp - 0x10]
229EC  or       ax, ax
229EE  je       0x229fc
229F0  cmp      ax, 4
229F3  je       0x229fc
229F5  cmp      ax, 6
229F8  je       0x229fc
229FA  jmp      0x22a13
229FC  push     word ptr [0x6312]
22A00  push     word ptr [0x6310]
22A04  push     ds
22A05  mov      ax, 0xc858
22A08  push     ax
22A09  lcall    0, 0x3c95
22A0E  add      sp, 8
22A11  jmp      0x22a46
22A13  cmp      word ptr [bp + 0x14], 1
22A17  jne      0x22a2f
22A19  cmp      word ptr [bp + 0x16], 1
22A1D  jne      0x22a25
22A1F  cmp      word ptr [bp + 0x12], 0
22A23  je       0x22a2f
22A25  push     word ptr [0x6312]
22A29  push     word ptr [0x6310]
22A2D  jmp      0x22a37
22A2F  push     word ptr [0x630e]
22A33  push     word ptr [0x630c]
22A37  push     ds
22A38  mov      ax, 0xc858
22A3B  push     ax
22A3C  lcall    0, 0x3c95
22A41  add      sp, 8
22A44  jmp      0x22a46
22A46  cmp      word ptr [bp + 0x14], 1
22A4A  jne      0x22a65
22A4C  test     word ptr [bp + 0xe], 2
22A51  je       0x22a65
22A53  push     ds
22A54  mov      ax, 0xb996
22A57  push     ax
22A58  push     ds
22A59  mov      ax, 0xc858
22A5C  push     ax
22A5D  lcall    0, 0x3c95
22A62  add      sp, 8
22A65  test     word ptr [bp + 0xe], 0x10
22A6A  je       0x22a7e
22A6C  push     ds
22A6D  mov      ax, 0xb99a
22A70  push     ax
22A71  push     ds
22A72  mov      ax, 0xc858
22A75  push     ax
22A76  lcall    0, 0x3c95
22A7B  add      sp, 8
22A7E  jmp      0x22784
22A81  pop      di
22A82  pop      si
22A83  mov      sp, bp
22A85  pop      bp
22A86  retf

; participle
22A87  push     bp
22A88  mov      bp, sp
22A8A  sub      sp, 0x12
22A8D  push     si
22A8E  push     di
22A8F  mov      word ptr [bp - 0xa], 0
22A94  push     word ptr [bp + 0xa]
22A97  push     word ptr [bp + 8]
22A9A  lcall    0, 0x3df1
22A9F  pop      cx
22AA0  pop      cx
22AA1  mov      di, ax
22AA3  mov      ax, word ptr [bp + 0xc]
22AA6  or       ax, ax
22AA8  je       0x22ab1
22AAA  cmp      ax, 1
22AAD  je       0x22abb
22AAF  jmp      0x22ac5
22AB1  mov      word ptr [bp - 0xc], ds
22AB4  mov      word ptr [bp - 0xe], 0x5a50
22AB9  jmp      0x22ac7
22ABB  mov      word ptr [bp - 0xc], ds
22ABE  mov      word ptr [bp - 0xe], 0x5e90
22AC3  jmp      0x22ac7
22AC5  jmp      0x22ab1
22AC7  cmp      word ptr [bp + 0xe], 0x47
22ACB  jne      0x22ad4
22ACD  mov      word ptr [bp - 0x12], 8
22AD2  jmp      0x22b00
22AD4  cmp      word ptr [bp + 0x12], 1
22AD8  jne      0x22aee
22ADA  cmp      word ptr [bp + 0x10], 0
22ADE  je       0x22ae7
22AE0  mov      word ptr [bp - 0x12], 0xc
22AE5  jmp      0x22aec
22AE7  mov      word ptr [bp - 0x12], 0xb
22AEC  jmp      0x22b00
22AEE  cmp      word ptr [bp + 0x10], 0
22AF2  je       0x22afb
22AF4  mov      word ptr [bp - 0x12], 0xa
22AF9  jmp      0x22b00
22AFB  mov      word ptr [bp - 0x12], 9
22B00  cmp      word ptr [bp + 0x10], 0
22B04  jne      0x22b4b
22B06  cmp      di, 2
22B09  jle      0x22b4b
22B0B  push     word ptr [0x630e]
22B0F  push     word ptr [0x630c]
22B13  push     di
22B14  push     word ptr [bp + 0xa]
22B17  push     word ptr [bp + 8]
22B1A  lcall    0x2104, 2
22B1F  add      sp, 0xa
22B22  cmp      ax, 2
22B25  je       0x22b43
22B27  push     word ptr [0x6312]
22B2B  push     word ptr [0x6310]
22B2F  push     di
22B30  push     word ptr [bp + 0xa]
22B33  push     word ptr [bp + 8]
22B36  lcall    0x2104, 2
22B3B  add      sp, 0xa
22B3E  cmp      ax, 2
22B41  jne      0x22b4b
22B43  mov      word ptr [bp - 0xa], 1
22B48  sub      di, 2
22B4B  mov      ax, word ptr [bp + 6]
22B4E  mov      dx, 6
22B51  imul     dx
22B53  les      bx, ptr [bp - 0xe]
22B56  add      bx, ax
22B58  mov      ax, di
22B5A  sub      ax, word ptr es:[bx]
22B5D  mov      si, ax
22B5F  or       si, si
22B61  jle      0x22b7e
22B63  push     si
22B64  push     word ptr [bp + 0xa]
22B67  push     word ptr [bp + 8]
22B6A  push     ds
22B6B  mov      ax, 0xc858
22B6E  push     ax
22B6F  lcall    0, 0x3ecf
22B74  add      sp, 0xa
22B77  mov      byte ptr [si - 0x37a8], 0
22B7C  jmp      0x22b91
22B7E  push     word ptr [bp + 0xa]
22B81  push     word ptr [bp + 8]
22B84  push     ds
22B85  mov      ax, 0xc858
22B88  push     ax
22B89  lcall    0, 0x3d41
22B8E  add      sp, 8
22B91  mov      ax, word ptr [bp + 6]
22B94  mov      dx, 6
22B97  imul     dx
22B99  les      bx, ptr [bp - 0xe]
22B9C  add      bx, ax
22B9E  mov      ax, word ptr es:[bx + 4]
22BA2  mov      dx, word ptr es:[bx + 2]
22BA6  mov      word ptr [bp - 2], ax
22BA9  mov      word ptr [bp - 4], dx
22BAC  mov      word ptr [bp - 0x10], 0
22BB1  jmp      0x22bdc
22BB3  mov      ax, 0x20
22BB6  push     ax
22BB7  push     word ptr [bp - 2]
22BBA  push     word ptr [bp - 4]
22BBD  lcall    0, 0x3cd4
22BC2  add      sp, 6
22BC5  mov      word ptr [bp - 2], dx
22BC8  mov      word ptr [bp - 4], ax
22BCB  or       ax, dx
22BCD  jne      0x22bd6
22BCF  xor      dx, dx
22BD1  xor      ax, ax
22BD3  jmp      0x22caa
22BD6  inc      word ptr [bp - 0x10]
22BD9  inc      word ptr [bp - 4]
22BDC  mov      ax, word ptr [bp - 0x10]
22BDF  cmp      ax, word ptr [bp - 0x12]
22BE2  jl       0x22bb3
22BE4  les      bx, ptr [bp - 4]
22BE7  cmp      byte ptr es:[bx], 0x2d
22BEB  jne      0x22bef
22BED  jmp      0x22bcf
22BEF  les      bx, ptr [bp - 4]
22BF2  cmp      byte ptr es:[bx], 0x3d
22BF6  je       0x22c59
22BF8  or       si, si
22BFA  jne      0x22c01
22BFC  mov      byte ptr [si - 0x37a8], 0
22C01  mov      ax, 0x20
22C04  push     ax
22C05  push     word ptr [bp - 2]
22C08  push     word ptr [bp - 4]
22C0B  lcall    0, 0x3cd4
22C10  add      sp, 6
22C13  mov      word ptr [bp - 6], dx
22C16  mov      word ptr [bp - 8], ax
22C19  mov      ax, word ptr [bp - 8]
22C1C  or       ax, word ptr [bp - 6]
22C1F  jne      0x22c36
22C21  push     word ptr [bp - 2]
22C24  push     word ptr [bp - 4]
22C27  push     ds
22C28  mov      ax, 0xc858
22C2B  push     ax
22C2C  lcall    0, 0x3c95
22C31  add      sp, 8
22C34  jmp      0x22c59
22C36  mov      ax, word ptr [bp - 8]
22C39  sub      ax, word ptr [bp - 4]
22C3C  mov      si, ax
22C3E  push     si
22C3F  push     word ptr [bp - 2]
22C42  push     word ptr [bp - 4]
22C45  push     ds
22C46  mov      ax, 0xc858
22C49  push     ax
22C4A  lcall    0, 0x3e34
22C4F  add      sp, 0xa
22C52  mov      bx, si
22C54  mov      byte ptr [bx + di - 0x37a8], 0
22C59  cmp      word ptr [bp - 0xa], 0
22C5D  je       0x22ca2
22C5F  mov      ax, word ptr [bp - 0x10]
22C62  cmp      ax, 8
22C65  je       0x22c69
22C67  jmp      0x22c98
22C69  cmp      word ptr [bp + 0xc], 0
22C6D  je       0x22c81
22C6F  push     ds
22C70  mov      ax, 0xb99e
22C73  push     ax
22C74  push     ds
22C75  mov      ax, 0xc858
22C78  push     ax
22C79  lcall    0, 0x3c95
22C7E  add      sp, 8
22C81  push     word ptr [0x6312]
22C85  push     word ptr [0x6310]
22C89  push     ds
22C8A  mov      ax, 0xc858
22C8D  push     ax
22C8E  lcall    0, 0x3c95
22C93  add      sp, 8
22C96  jmp      0x22ca2
22C98  push     word ptr [0x630e]
22C9C  push     word ptr [0x630c]
22CA0  jmp      0x22c89
22CA2  mov      dx, ds
22CA4  mov      ax, 0xc858
22CA7  jmp      0x22bd3
22CAA  pop      di
22CAB  pop      si
22CAC  mov      sp, bp
22CAE  pop      bp
22CAF  retf

; ends_with
24A42  push     bp
24A43  mov      bp, sp
24A45  push     si
24A46  push     di
24A47  mov      si, word ptr [bp + 0xa]
24A4A  push     word ptr [bp + 0xe]
24A4D  push     word ptr [bp + 0xc]
24A50  lcall    0, 0x3df1
24A55  pop      cx
24A56  pop      cx
24A57  mov      di, ax
24A59  sub      si, di
24A5B  or       si, si
24A5D  jl       0x24a7f
24A5F  push     di
24A60  push     word ptr [bp + 0xe]
24A63  push     word ptr [bp + 0xc]
24A66  mov      ax, word ptr [bp + 6]
24A69  add      ax, si
24A6B  push     word ptr [bp + 8]
24A6E  push     ax
24A6F  lcall    0, 0x3e97
24A74  add      sp, 0xa
24A77  or       ax, ax
24A79  jne      0x24a7f
24A7B  mov      ax, di
24A7D  jmp      0x24a83
24A7F  xor      ax, ax
24A81  jmp      0x24a7d
24A83  pop      di
24A84  pop      si
24A85  pop      bp
24A86  retf
