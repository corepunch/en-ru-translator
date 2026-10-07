#!/usr/bin/env python3
"""Execute the original lexical metadata decoder; compare its field writes."""
import random
import subprocess
import tempfile
from pathlib import Path
from ltpro_native_probe import Machine,lua_value

FIELDS=(0x0B,0x0C,0x0F,0x66,0x68,0x6A,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79)

def original(image,case,cache):
    m=Machine(image);m.cache=cache;m.r.update(cs=0xA4F,ip=0xC0F)
    for at in FIELDS: m.write(0x80000+at,1,case['initial'].get(str(at),0))
    m.write(0x8000C,1,ord(case['tag']))
    m.write(0x22d50+0xBBAE,2,int(case.get('transliterate',True)))
    for at,value in [(0x80012,case.get('source','')), (0x8011C,case.get('translation',''))]:
        data=value.encode('cp866')+b'\0';m.mem[at:at+len(data)]=data
    data=case['payload'].encode('cp866')+b'\0';m.mem[0xD0100:0xD0100+len(data)]=data
    for value in reversed([0,0xD000,0x100,0xD000,0,0x8000]): m.push(value)
    m.push(0xFFFF);m.push(0xFFFF);m.run()
    values=[str((m.reg('ax')-0x100)&0xFFFF)]+[str(m.read(0x80000+at,1)) for at in FIELDS]
    return ','.join(values+[m.cstring(0x8011C).hex()])

def main():
    image=Path('LTGOLD/LTPRO.EXE').read_bytes();rng=random.Random(1993)
    cases=[]
    for tag in '#ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz':
        for payload in ['слово','0слово','123слово','9999слово','ВПвb','Рпредлог','Бпрефикс','Пслово','Тслово','001Рслово','001Дслово','001Вслово','001Тслово','001Пслово']:
            for _ in range(3):
                initial={str(at):rng.randrange(256) for at in FIELDS}
                cases.append({'tag':tag,'payload':payload,'initial':initial})
    for tag in ['#','N','A','D','V']:
        for payload in ['=','%','=имя','%имя','=ignored','%ignored']:
            for transliterate in [False,True]:
                for marker in [0,0x77]:
                    for source in ['Aaron','ABC','Ivanova','th','']:
                        cases.append({'tag':tag,'payload':payload,'initial':{'11':1,'15':marker},
                                      'source':source,'translation':'kept','transliterate':transliterate})
    cache={};expected=[original(image,case,cache) for case in cases]
    with tempfile.TemporaryDirectory(prefix='ltpro-readings-') as directory:
        path=Path(directory)/'fixtures.lua';path.write_text('return '+lua_value(cases))
        actual=subprocess.check_output(['lua','tools/ltpro_readings_probe.lua',str(path)],text=True).splitlines()
    assert len(actual)==len(expected)
    mismatches=[(i,a,b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
    for i,a,b in mismatches[:10]:print('DIFF',i,cases[i],'EXE',a,'Lua',b)
    print(f'LTPRO reading metadata vs Lua: {len(cases)-len(mismatches)}/{len(cases)}')
    raise SystemExit(bool(mismatches))

if __name__=='__main__':main()
