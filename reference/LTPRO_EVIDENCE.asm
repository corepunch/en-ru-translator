; LTPRO.EXE SHA256 6a2036c2fbc629d0317bf02acbb1e6ebd82ceecb2d11f609c6460cc0c32dc4fe
; Captured 2026-10-06 with installed Capstone in x86 16-bit mode.
; Addresses are file offsets. Relative branch labels use those coordinates.
; Far-call operands are original MZ segment:offset values (load relocation unapplied).
; These excerpts establish dispatch/layout; they are not a full decompilation.

; T1 first successful rule exit
124A8  c45ef6         les     bx, ptr [bp - 0xa]
124AB  26ff7706       push    word ptr es:[bx + 6]
124AF  26ff7704       push    word ptr es:[bx + 4]
124B3  c45ef6         les     bx, ptr [bp - 0xa]
124B6  26ff7702       push    word ptr es:[bx + 2]
124BA  26ff37         push    word ptr es:[bx]
124BD  ff76fa         push    word ptr [bp - 6]
124C0  33c0           xor     ax, ax
124C2  50             push    ax
124C3  16             push    ss
124C4  8d86bef7       lea     ax, [bp - 0x842]
124C8  50             push    ax
124C9  9ab4011313     lcall   0x1313, 0x1b4
124CE  83c410         add     sp, 0x10
124D1  8946fe         mov     word ptr [bp - 2], ax
124D4  eb13           jmp     0x124e9
124D6  8346f60a       add     word ptr [bp - 0xa], 0xa
124DA  c45ef6         les     bx, ptr [bp - 0xa]
124DD  268b07         mov     ax, word ptr es:[bx]
124E0  260b4702       or      ax, word ptr es:[bx + 2]
124E4  7403           je      0x124e9
124E6  e908f8         jmp     0x11cf1

; T2 handler switch
125B1  c45ef2         les     bx, ptr [bp - 0xe]
125B4  268b5f08       mov     bx, word ptr es:[bx + 8]
125B8  4b             dec     bx
125B9  83fb3c         cmp     bx, 0x3c
125BC  7603           jbe     0x125c1
125BE  e9af10         jmp     0x13670
125C1  d1e3           shl     bx, 1
125C3  2effa75926     jmp     word ptr cs:[bx + 0x2659]

; T2 rewrite and scan advance
13670  c45ef2         les     bx, ptr [bp - 0xe]
13673  26ff7706       push    word ptr es:[bx + 6]
13677  26ff7704       push    word ptr es:[bx + 4]
1367B  c45ef2         les     bx, ptr [bp - 0xe]
1367E  26ff7702       push    word ptr es:[bx + 2]
13682  26ff37         push    word ptr es:[bx]
13685  ff76fa         push    word ptr [bp - 6]
13688  57             push    di
13689  16             push    ss
1368A  8d86bef7       lea     ax, [bp - 0x842]
1368E  50             push    ax
1368F  9ab4011313     lcall   0x1313, 0x1b4
13694  83c410         add     sp, 0x10
13697  8946fe         mov     word ptr [bp - 2], ax
1369A  8b7efa         mov     di, word ptr [bp - 6]
1369D  47             inc     di
1369E  a1b1c7         mov     ax, word ptr [0xc7b1]
136A1  48             dec     ax
136A2  3bc7           cmp     ax, di
136A4  7e03           jle     0x136a9
136A6  e9b2ee         jmp     0x1255b
136A9  837efe00       cmp     word ptr [bp - 2], 0
136AD  741c           je      0x136cb
136AF  16             push    ss
136B0  8d86bef7       lea     ax, [bp - 0x842]
136B4  50             push    ax
136B5  ff7608         push    word ptr [bp + 8]
136B8  ff7606         push    word ptr [bp + 6]
136BB  9a0e001313     lcall   0x1313, 0xe
136C0  83c408         add     sp, 8
136C3  a3b1c7         mov     word ptr [0xc7b1], ax
136C6  c746fe0000     mov     word ptr [bp - 2], 0
136CB  8346f20a       add     word ptr [bp - 0xe], 0xa
136CF  c45ef2         les     bx, ptr [bp - 0xe]
136D2  268b07         mov     ax, word ptr es:[bx]
136D5  260b4702       or      ax, word ptr es:[bx + 2]
136D9  7403           je      0x136de
136DB  e977ee         jmp     0x12555

; T4 pointer and trailing handler
14954  c746f8dc2d     mov     word ptr [bp - 8], 0x2ddc
14959  e91e17         jmp     0x1607a
1495C  33ff           xor     di, di
1495E  c746f20100     mov     word ptr [bp - 0xe], 1
14963  e9ff16         jmp     0x16065
14966  c45ef8         les     bx, ptr [bp - 8]
14969  26ff7702       push    word ptr es:[bx + 2]
1496D  26ff37         push    word ptr es:[bx]
14970  57             push    di
14971  16             push    ss
14972  8d86b8f7       lea     ax, [bp - 0x848]
14976  50             push    ax
14977  9a670a1313     lcall   0x1313, 0xa67
1497C  83c40a         add     sp, 0xa
1497F  8946fc         mov     word ptr [bp - 4], ax
14982  0bc0           or      ax, ax
14984  7503           jne     0x14989
14986  e9db16         jmp     0x16064
14989  8bdf           mov     bx, di
1498B  b102           mov     cl, 2
1498D  d3e3           shl     bx, cl
1498F  8d86b8f7       lea     ax, [bp - 0x848]
14993  03d8           add     bx, ax
14995  368b4702       mov     ax, word ptr ss:[bx + 2]
14999  368b17         mov     dx, word ptr ss:[bx]
1499C  8946f0         mov     word ptr [bp - 0x10], ax
1499F  8956ee         mov     word ptr [bp - 0x12], dx
149A2  8b5efc         mov     bx, word ptr [bp - 4]
149A5  b102           mov     cl, 2
149A7  d3e3           shl     bx, cl
149A9  8d86b8f7       lea     ax, [bp - 0x848]
149AD  03d8           add     bx, ax
149AF  368b4702       mov     ax, word ptr ss:[bx + 2]
149B3  368b17         mov     dx, word ptr ss:[bx]
149B6  8946ec         mov     word ptr [bp - 0x14], ax
149B9  8956ea         mov     word ptr [bp - 0x16], dx
149BC  c45ef8         les     bx, ptr [bp - 8]
149BF  268a4708       mov     al, byte ptr es:[bx + 8]
149C3  b400           mov     ah, 0
149C5  48             dec     ax
149C6  8bd8           mov     bx, ax
149C8  83fb62         cmp     bx, 0x62
149CB  7603           jbe     0x149d0

; T5/T6 scanner initialization
161C2  be0100         mov     si, 1
161C5  e95605         jmp     0x1671e
161C8  8c5ef8         mov     word ptr [bp - 8], ds
161CB  c746f6f03f     mov     word ptr [bp - 0xa], 0x3ff0
161D0  e93b05         jmp     0x1670e

; T5/T6 specialized literal-tag matcher
1732D  55             push    bp
1732E  8bec           mov     bp, sp
17330  8b560a         mov     dx, word ptr [bp + 0xa]
17333  eb22           jmp     0x17357
17335  8bc2           mov     ax, dx
17337  b102           mov     cl, 2
17339  d3e0           shl     ax, cl
1733B  c45e06         les     bx, ptr [bp + 6]
1733E  03d8           add     bx, ax
17340  26c41f         les     bx, ptr es:[bx]
17343  268a470c       mov     al, byte ptr es:[bx + 0xc]
17347  c45e0c         les     bx, ptr [bp + 0xc]
1734A  263a07         cmp     al, byte ptr es:[bx]
1734D  7404           je      0x17353
1734F  33c0           xor     ax, ax
17351  eb12           jmp     0x17365
17353  ff460c         inc     word ptr [bp + 0xc]
17356  42             inc     dx
17357  c45e0c         les     bx, ptr [bp + 0xc]
1735A  26803f00       cmp     byte ptr es:[bx], 0
1735E  75d5           jne     0x17335
17360  8bc2           mov     ax, dx
17362  48             dec     ax
17363  ebec           jmp     0x17351
17365  5d             pop     bp
17366  cb             retf

; T5/T6 sequential swaps
165A1  33ff           xor     di, di
165A3  e9dd00         jmp     0x16683
165A6  c45ef6         les     bx, ptr [bp - 0xa]
165A9  26c45f04       les     bx, ptr es:[bx + 4]
165AD  03df           add     bx, di
165AF  268a07         mov     al, byte ptr es:[bx]
165B2  b400           mov     ah, 0
165B4  05cfff         add     ax, 0xffcf
165B7  8946f4         mov     word ptr [bp - 0xc], ax
165BA  397ef4         cmp     word ptr [bp - 0xc], di
165BD  7503           jne     0x165c2
165BF  e9c000         jmp     0x16682
165C2  8bde           mov     bx, si
165C4  035ef4         add     bx, word ptr [bp - 0xc]
165C7  b102           mov     cl, 2
165C9  d3e3           shl     bx, cl
165CB  8d86def7       lea     ax, [bp - 0x822]
165CF  03d8           add     bx, ax
165D1  36ff7702       push    word ptr ss:[bx + 2]
165D5  36ff37         push    word ptr ss:[bx]
165D8  8bde           mov     bx, si
165DA  035ef4         add     bx, word ptr [bp - 0xc]
165DD  b102           mov     cl, 2
165DF  d3e3           shl     bx, cl
165E1  8d86daf7       lea     ax, [bp - 0x826]
165E5  03d8           add     bx, ax
165E7  36ff7702       push    word ptr ss:[bx + 2]
165EB  36ff37         push    word ptr ss:[bx]
165EE  8bde           mov     bx, si
165F0  03df           add     bx, di
165F2  b102           mov     cl, 2
165F4  d3e3           shl     bx, cl
165F6  8d86def7       lea     ax, [bp - 0x822]
165FA  03d8           add     bx, ax
165FC  36ff7702       push    word ptr ss:[bx + 2]
16600  36ff37         push    word ptr ss:[bx]
16603  8bde           mov     bx, si
16605  03df           add     bx, di
16607  b102           mov     cl, 2
16609  d3e3           shl     bx, cl
1660B  8d86daf7       lea     ax, [bp - 0x826]
1660F  03d8           add     bx, ax
16611  36ff7702       push    word ptr ss:[bx + 2]
16615  36ff37         push    word ptr ss:[bx]
16618  9adf121313     lcall   0x1313, 0x12df
1661D  83c410         add     sp, 0x10
16620  8bde           mov     bx, si
16622  03df           add     bx, di
16624  b102           mov     cl, 2
16626  d3e3           shl     bx, cl
16628  8d86def7       lea     ax, [bp - 0x822]
1662C  03d8           add     bx, ax
1662E  368b4702       mov     ax, word ptr ss:[bx + 2]
16632  368b17         mov     dx, word ptr ss:[bx]
16635  8946ee         mov     word ptr [bp - 0x12], ax
16638  8956ec         mov     word ptr [bp - 0x14], dx
1663B  8bde           mov     bx, si
1663D  035ef4         add     bx, word ptr [bp - 0xc]
16640  b102           mov     cl, 2
16642  d3e3           shl     bx, cl
16644  8d86def7       lea     ax, [bp - 0x822]
16648  03d8           add     bx, ax
1664A  368b4702       mov     ax, word ptr ss:[bx + 2]
1664E  368b17         mov     dx, word ptr ss:[bx]
16651  8bde           mov     bx, si
16653  03df           add     bx, di
16655  b102           mov     cl, 2
16657  d3e3           shl     bx, cl
16659  8d8edef7       lea     cx, [bp - 0x822]
1665D  03d9           add     bx, cx
1665F  36894702       mov     word ptr ss:[bx + 2], ax
16663  368917         mov     word ptr ss:[bx], dx
16666  8bde           mov     bx, si
16668  035ef4         add     bx, word ptr [bp - 0xc]
1666B  b102           mov     cl, 2
1666D  d3e3           shl     bx, cl
1666F  8d86def7       lea     ax, [bp - 0x822]
16673  03d8           add     bx, ax
16675  8b46ee         mov     ax, word ptr [bp - 0x12]
16678  8b56ec         mov     dx, word ptr [bp - 0x14]
1667B  36894702       mov     word ptr ss:[bx + 2], ax
1667F  368917         mov     word ptr ss:[bx], dx
16682  47             inc     di
16683  c45ef6         les     bx, ptr [bp - 0xa]
16686  26c45f04       les     bx, ptr es:[bx + 4]
1668A  03df           add     bx, di
1668C  26803f00       cmp     byte ptr es:[bx], 0
16690  7403           je      0x16695
16692  e911ff         jmp     0x165a6

; T5/T6 next record vs next span
16702  8b46fc         mov     ax, word ptr [bp - 4]
16705  48             dec     ax
16706  03f0           add     si, ax
16708  eb13           jmp     0x1671d
1670A  8346f60a       add     word ptr [bp - 0xa], 0xa
1670E  c45ef6         les     bx, ptr [bp - 0xa]
16711  268b07         mov     ax, word ptr es:[bx]
16714  260b4702       or      ax, word ptr es:[bx + 2]
16718  7403           je      0x1671d
1671A  e9b6fa         jmp     0x161d3
1671D  46             inc     si
1671E  a1b1c7         mov     ax, word ptr [0xc7b1]
16721  48             dec     ax
16722  3bc6           cmp     ax, si
16724  7e03           jle     0x16729
16726  e99ffa         jmp     0x161c8

; general pattern matcher dispatch
175C0  c45e0c         les     bx, ptr [bp + 0xc]
175C3  268a07         mov     al, byte ptr es:[bx]
175C6  b400           mov     ah, 0
175C8  8946e8         mov     word ptr [bp - 0x18], ax
175CB  b90600         mov     cx, 6
175CE  bbc712         mov     bx, 0x12c7
175D1  2e8b07         mov     ax, word ptr cs:[bx]
175D4  3b46e8         cmp     ax, word ptr [bp - 0x18]
175D7  7408           je      0x175e1
175D9  83c302         add     bx, 2
175DC  e2f3           loop    0x175d1
175DE  e99d07         jmp     0x17d7e
175E1  2eff670c       jmp     word ptr cs:[bx + 0xc]

; T7 alternate table selection
17ECE  8c5efc         mov     word ptr [bp - 4], ds
17ED1  c746fa4245     mov     word ptr [bp - 6], 0x4542
17ED6  eb0c           jmp     0x17ee4
17ED8  8c5efc         mov     word ptr [bp - 4], ds
17EDB  c746fa6246     mov     word ptr [bp - 6], 0x4662
17EE0  eb02           jmp     0x17ee4
17EE2  ebc5           jmp     0x17ea9

; T7 endpoint order and handler dispatch
17F26  c45efa         les     bx, ptr [bp - 6]
17F29  26837f0400     cmp     word ptr es:[bx + 4], 0
17F2E  7435           je      0x17f65
17F30  8b5efe         mov     bx, word ptr [bp - 2]
17F33  b102           mov     cl, 2
17F35  d3e3           shl     bx, cl
17F37  8d86e6f7       lea     ax, [bp - 0x81a]
17F3B  03d8           add     bx, ax
17F3D  368b4702       mov     ax, word ptr ss:[bx + 2]
17F41  368b17         mov     dx, word ptr ss:[bx]
17F44  8946f6         mov     word ptr [bp - 0xa], ax
17F47  8956f4         mov     word ptr [bp - 0xc], dx
17F4A  8bdf           mov     bx, di
17F4C  b102           mov     cl, 2
17F4E  d3e3           shl     bx, cl
17F50  8d86e6f7       lea     ax, [bp - 0x81a]
17F54  03d8           add     bx, ax
17F56  368b4702       mov     ax, word ptr ss:[bx + 2]
17F5A  368b17         mov     dx, word ptr ss:[bx]
17F5D  8946f2         mov     word ptr [bp - 0xe], ax
17F60  8956f0         mov     word ptr [bp - 0x10], dx
17F63  eb33           jmp     0x17f98
17F65  8b5efe         mov     bx, word ptr [bp - 2]
17F68  b102           mov     cl, 2
17F6A  d3e3           shl     bx, cl
17F6C  8d86e6f7       lea     ax, [bp - 0x81a]
17F70  03d8           add     bx, ax
17F72  368b4702       mov     ax, word ptr ss:[bx + 2]
17F76  368b17         mov     dx, word ptr ss:[bx]
17F79  8946f2         mov     word ptr [bp - 0xe], ax
17F7C  8956f0         mov     word ptr [bp - 0x10], dx
17F7F  8bdf           mov     bx, di
17F81  b102           mov     cl, 2
17F83  d3e3           shl     bx, cl
17F85  8d86e6f7       lea     ax, [bp - 0x81a]
17F89  03d8           add     bx, ax
17F8B  368b4702       mov     ax, word ptr ss:[bx + 2]
17F8F  368b17         mov     dx, word ptr ss:[bx]
17F92  8946f6         mov     word ptr [bp - 0xa], ax
17F95  8956f4         mov     word ptr [bp - 0xc], dx
17F98  c45efa         les     bx, ptr [bp - 6]
17F9B  268b5f06       mov     bx, word ptr es:[bx + 6]
17F9F  4b             dec     bx
17FA0  83fb16         cmp     bx, 0x16
17FA3  7603           jbe     0x17fa8
17FA5  e9a70b         jmp     0x18b4f
17FA8  d1e3           shl     bx, 1
17FAA  2effa7f50c     jmp     word ptr cs:[bx + 0xcf5]

; T8 per-position table initialization and handler dispatch
1D276  be0100         mov     si, 1
1D279  e99e2a         jmp     0x1fd1a
1D27C  8c5efc         mov     word ptr [bp - 4], ds
1D27F  c746fae449     mov     word ptr [bp - 6], 0x49e4
1D284  e94a2a         jmp     0x1fcd1
1D287  c45efa         les     bx, ptr [bp - 6]
1D28A  26ff7702       push    word ptr es:[bx + 2]
1D28E  26ff37         push    word ptr es:[bx]
1D291  56             push    si
1D292  ff36fcc7       push    word ptr [0xc7fc]
1D296  ff36fac7       push    word ptr [0xc7fa]
1D29A  9a35013d1c     lcall   0x1c3d, 0x135
1D29F  83c40a         add     sp, 0xa
1D2A2  8946fe         mov     word ptr [bp - 2], ax
1D2A5  0bc0           or      ax, ax
1D2A7  7503           jne     0x1d2ac
1D2A9  e9212a         jmp     0x1fccd
1D2AC  c45efa         les     bx, ptr [bp - 6]
1D2AF  268b5f06       mov     bx, word ptr es:[bx + 6]
1D2B3  4b             dec     bx
1D2B4  83fb45         cmp     bx, 0x45
1D2B7  7603           jbe     0x1d2bc
1D2B9  e90f2a         jmp     0x1fccb
1D2BC  d1e3           shl     bx, 1
1D2BE  2effa7e52a     jmp     word ptr cs:[bx + 0x2ae5]

; T8 record iteration and next position
1FCCB  eb00           jmp     0x1fccd
1FCCD  8346fa08       add     word ptr [bp - 6], 8
1FCD1  c45efa         les     bx, ptr [bp - 6]
1FCD4  268b07         mov     ax, word ptr es:[bx]
1FCD7  260b4702       or      ax, word ptr es:[bx + 2]
1FCDB  7403           je      0x1fce0
1FCDD  e9a7d5         jmp     0x1d287
1FCE0  ff36fcc7       push    word ptr [0xc7fc]
1FCE4  ff36fac7       push    word ptr [0xc7fa]
1FCE8  56             push    si
1FCE9  8bc6           mov     ax, si
1FCEB  ba0c00         mov     dx, 0xc
1FCEE  f7ea           imul    dx
1FCF0  c41efac7       les     bx, ptr [0xc7fa]
1FCF4  03d8           add     bx, ax
1FCF6  268a07         mov     al, byte ptr es:[bx]
1FCF9  b400           mov     ah, 0
1FCFB  50             push    ax
1FCFC  8bc6           mov     ax, si
1FCFE  ba0c00         mov     dx, 0xc
1FD01  f7ea           imul    dx
1FD03  8b16fac7       mov     dx, word ptr [0xc7fa]
1FD07  03d0           add     dx, ax
1FD09  83c204         add     dx, 4
1FD0C  ff36fcc7       push    word ptr [0xc7fc]
1FD10  52             push    dx
1FD11  9a04004914     lcall   0x1449, 4
1FD16  83c40c         add     sp, 0xc
1FD19  46             inc     si
1FD1A  a1fec7         mov     ax, word ptr [0xc7fe]
1FD1D  48             dec     ax
1FD1E  3bc6           cmp     ax, si
1FD20  7e03           jle     0x1fd25
1FD22  e957d5         jmp     0x1d27c
