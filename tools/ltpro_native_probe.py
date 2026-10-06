#!/usr/bin/env python3
"""Exercise the original reorder routine without DOS; requires the installed Capstone.

This deliberately limited 8086 harness rejects unsupported instructions. It executes
LTPRO's actual vector/linked-swap/reorder code; only C string/free primitives are stubbed.
It is a verification tool, not a translator or a replacement DOS environment.
"""
import argparse
import json
import random
import struct
import subprocess
import tempfile
from pathlib import Path
from capstone import Cs, CS_ARCH_X86, CS_MODE_16
from capstone.x86 import X86_OP_REG, X86_OP_IMM, X86_OP_MEM


class Machine:
    def __init__(self, image):
        self.mem = bytearray(1 << 20)
        header = struct.unpack_from('<H', image, 8)[0] * 16
        self.mem[:len(image) - header] = image[header:]
        self.r = dict.fromkeys(('ax','bx','cx','dx','si','di','bp','sp','cs','ds','es','ss','ip'), 0)
        self.r.update(ds=0x22d5, ss=0x6000, sp=0xff00, cs=0x1279, ip=0xd)
        self.md = Cs(CS_ARCH_X86, CS_MODE_16)
        self.md.detail = True
        self.cache = {}
        self.zf = self.sf = self.of = self.cf = False
        self.steps = 0
        self.before_instruction = None
        self.heap_next = 0xB0000
        self.allocations = []
        self.calloc_failure = False

    def reg(self, name, value=None):
        parent = name if name in self.r else name[0] + 'x'
        shift = 8 if name.endswith('h') else 0
        mask = 0xffff if name in self.r else 0xff
        if value is None:
            return (self.r[parent] >> shift) & mask
        self.r[parent] = (self.r[parent] & ~(mask << shift)) | ((value & mask) << shift)

    def read(self, address, size):
        assert 0 <= address <= len(self.mem) - size
        return int.from_bytes(self.mem[address:address+size], 'little')

    def write(self, address, size, value):
        assert 0 <= address <= len(self.mem) - size
        self.mem[address:address+size] = (value & ((1 << (8*size))-1)).to_bytes(size, 'little')

    def address(self, ins, op, effective=False):
        m = op.mem
        base = ins.reg_name(m.base) if m.base else None
        offset = m.disp + (self.reg(base) if base else 0)
        if m.index:
            offset += self.reg(ins.reg_name(m.index)) * m.scale
        offset &= 0xffff
        segment = ins.reg_name(m.segment) if m.segment else ('ss' if base in ('bp','sp') else 'ds')
        return offset if effective else (self.reg(segment)*16+offset) & 0xfffff

    def get(self, ins, op):
        if op.type == X86_OP_REG: return self.reg(ins.reg_name(op.reg))
        if op.type == X86_OP_IMM: return op.imm
        if op.type == X86_OP_MEM: return self.read(self.address(ins,op),op.size)
        raise AssertionError('operand')

    def set(self, ins, op, value):
        if op.type == X86_OP_REG: self.reg(ins.reg_name(op.reg),value)
        elif op.type == X86_OP_MEM: self.write(self.address(ins,op),op.size,value)
        else: raise AssertionError('destination')

    def push(self, value):
        self.reg('sp',self.reg('sp')-2)
        self.write(self.reg('ss')*16+self.reg('sp'),2,value)

    def pop(self):
        value=self.read(self.reg('ss')*16+self.reg('sp'),2)
        self.reg('sp',self.reg('sp')+2)
        return value

    def flags(self, a, b, value, bits, subtraction=False):
        mask=(1<<bits)-1; sign=1<<(bits-1); value &= mask
        self.zf=value==0; self.sf=bool(value & sign)
        self.cf=a<b if subtraction else a+b>mask
        self.of=bool(((a^b) if subtraction else ~(a^b)) & (a^value) & sign)

    def cstring(self, pointer):
        end=self.mem.index(0,pointer)
        return bytes(self.mem[pointer:end])

    def library(self, segment, offset):
        if segment: return False
        sp=self.reg('ss')*16+self.reg('sp')
        ptr=lambda at: self.read(sp+at+2,2)*16+self.read(sp+at,2)
        if offset==0x3df1: self.reg('ax',len(self.cstring(ptr(0))))
        elif offset in (0x3db0,0x3d11):
            a,b=self.cstring(ptr(0)),self.cstring(ptr(4))
            # 0000:3DB0 folds ASCII a-z; 0000:3D11 is the exact byte comparison.
            if offset==0x3db0: a,b=a.upper(),b.upper()
            self.reg('ax',(a>b)-(a<b))
        elif offset==0x432:
            # Compiler block-copy helper uses CX bytes and callee-pops two pointers.
            source,dest,n=ptr(0),ptr(4),self.reg('cx')
            self.mem[dest:dest+n]=self.mem[source:source+n]
            self.reg('es',self.read(sp+6,2));self.reg('cx',0)
            self.zf=True;self.cf=self.sf=self.of=False
            self.reg('sp',self.reg('sp')+8)
        elif offset==0x3f44:
            haystack,chars=self.cstring(ptr(0)),self.cstring(ptr(4))
            found=next((i for i,c in enumerate(haystack) if c in chars),-1)
            self.reg('ax',self.read(sp,2)+found if found>=0 else 0)
            self.reg('dx',self.read(sp+2,2) if found>=0 else 0)
        elif offset in (0x3cd4,0x3f90,0x3fd9):
            target=bytes([self.read(sp+4,2)&255]) if offset!=0x3fd9 else self.cstring(ptr(4))
            haystack=self.cstring(ptr(0))
            found=haystack.rfind(target) if offset==0x3f90 else haystack.find(target)
            # Preserve the input segment: native callers subtract returned offsets.
            self.reg('ax',self.read(sp,2)+found if found>=0 else 0)
            self.reg('dx',self.read(sp+2,2) if found>=0 else 0)
        elif offset in (0x3d41,0x3ecf,0x3c95,0x3e34):
            dest,source=ptr(0),self.cstring(ptr(4))
            if offset==0x3ecf:
                n=self.read(sp+8,2);value=source[:n].ljust(n,b'\0')
            elif offset==0x3e34:
                dest+=len(self.cstring(dest));value=source[:self.read(sp+8,2)]+b'\0'
            elif offset==0x3c95:
                dest+=len(self.cstring(dest));value=source+b'\0'
            else:value=source+b'\0'
            self.mem[dest:dest+len(value)]=value
            self.reg('ax',self.read(sp,2));self.reg('dx',self.read(sp+2,2))
        elif offset==0x3e97:
            n=self.read(sp+8,2);a=self.cstring(ptr(0))[:n];b=self.cstring(ptr(4))[:n]
            self.reg('ax',(a>b)-(a<b))
        elif offset==0x1baa: pass  # free does not alter observable live-node fields
        elif offset==0x1951:
            # calloc is a library primitive; native record construction still runs.
            if self.calloc_failure:
                self.reg('ax',0);self.reg('dx',0)
                return True
            n=self.read(sp,2)*self.read(sp+2,2)
            address=self.heap_next;self.heap_next+=max(0x400,(n+15)&~15)
            assert self.heap_next<0xF0000,'probe heap exhausted'
            self.mem[address:address+n]=bytes(n)
            self.allocations.append(address)
            self.reg('ax',address&15);self.reg('dx',address>>4)
        else: return False
        return True

    def run(self):
        while (self.reg('cs'),self.reg('ip'))!=(0xffff,0xffff):
            if self.before_instruction and self.before_instruction(self): break
            key=(self.reg('cs'),self.reg('ip'))
            if key not in self.cache:
                physical=(key[0]*16+key[1])&0xfffff
                self.cache[key]=next(self.md.disasm(bytes(self.mem[physical:physical+16]),key[1],count=1))
            ins=self.cache[key]; self.steps+=1
            assert self.steps<1000000,'instruction limit'
            self.reg('ip',self.reg('ip')+ins.size)
            op=ins.operands; m=ins.mnemonic
            if m=='mov': self.set(ins,op[0],self.get(ins,op[1]))
            elif m=='push': self.push(self.get(ins,op[0]))
            elif m=='pop': self.set(ins,op[0],self.pop())
            elif m=='lea': self.set(ins,op[0],self.address(ins,op[1],True))
            elif m=='les':
                pointer=self.read(self.address(ins,op[1]),4)
                self.set(ins,op[0],pointer&0xffff);self.reg('es',pointer>>16)
            elif m in ('add','sub','cmp','xor','or','test','and'):
                a,b=self.get(ins,op[0]),self.get(ins,op[1]);bits=op[0].size*8;mask=(1<<bits)-1
                b &= mask
                value={'add':lambda:a+b,'sub':lambda:a-b,'cmp':lambda:a-b,'xor':lambda:a^b,
                       'or':lambda:a|b,'test':lambda:a&b,'and':lambda:a&b}[m]()
                self.flags(a,b,value,bits,m in ('sub','cmp'))
                if m in ('xor','or','test','and'):self.of=self.cf=False
                if m not in ('cmp','test'):self.set(ins,op[0],value)
            elif m in ('inc','dec'):
                a=self.get(ins,op[0]);delta=1 if m=='inc' else -1
                carry=self.cf;self.flags(a,1,a+delta,op[0].size*8,m=='dec');self.cf=carry
                self.set(ins,op[0],a+delta)
            elif m=='shl':
                a,n=self.get(ins,op[0]),self.get(ins,op[1]);self.set(ins,op[0],a<<n)
                self.zf=self.get(ins,op[0])==0
            elif m=='imul' and len(op)==1:
                signed=lambda v:v-65536 if v&0x8000 else v
                value=signed(self.reg('ax'))*signed(self.get(ins,op[0]))
                self.reg('ax',value);self.reg('dx',value>>16)
                self.cf=self.of=not -32768<=value<=32767
            elif m=='call':
                # Near calls in the large-model grammar explicitly push CS first.
                target=self.get(ins,op[0]);self.push(self.reg('ip'));self.reg('ip',target)
            elif m=='lcall':
                segment,offset=self.get(ins,op[0]),self.get(ins,op[1])
                if not self.library(segment,offset):
                    self.push(self.reg('cs'));self.push(self.reg('ip'))
                    self.reg('cs',segment);self.reg('ip',offset)
            elif m=='retf':
                self.reg('ip',self.pop());self.reg('cs',self.pop())
            elif m=='loop':
                self.reg('cx',self.reg('cx')-1)
                if self.reg('cx'):self.reg('ip',self.get(ins,op[0]))
            elif m in ('jmp','je','jne','jl','jle','jg','jge','jb','jbe','ja','jae'):
                condition={'jmp':True,'je':self.zf,'jne':not self.zf,'jl':self.sf!=self.of,
                           'jle':self.zf or self.sf!=self.of,'jg':not self.zf and self.sf==self.of,
                           'jge':self.sf==self.of,'jb':self.cf,'jbe':self.cf or self.zf,
                           'ja':not self.cf and not self.zf,'jae':not self.cf}[m]
                if condition:self.reg('ip',self.get(ins,op[0]))
            else:raise AssertionError(f'unsupported {key}: {ins.mnemonic} {ins.op_str}')

    def fixture(self, fields):
        addresses=[0x80000+i*0x200 for i in range(len(fields))]
        def far(address):return ((address>>4)<<16)|(address&15)
        for i,(address,field) in enumerate(zip(addresses,fields)):
            self.write(address,4,far(addresses[i+1]) if i+1<len(addresses) else 0)
            for key in ('12','15','102','114','118'):self.write(address+int(key),1,field.get(key,0))
            text=field.get('text','').encode('cp866')+b'\0';p=0xd0000+i*128
            self.mem[p:p+len(text)]=text;self.write(address+0x98,4,far(p))
        self.write(0x70000,4,far(addresses[0]))
        self.push(0x7000);self.push(0);self.push(0xffff);self.push(0xffff)
        self.run()
        result=[];pointer=self.read(0x70000,4);seen=set()
        while pointer:
            address=(pointer>>16)*16+(pointer&0xffff)
            assert address in addresses and address not in seen,'invalid linked list'
            seen.add(address);result.append(addresses.index(address)+1)
            pointer=self.read(address,4)
        return result,[self.read(a+12,1) for a in addresses]


class GoldMachine(Machine):
    def __init__(self, image):
        super().__init__(image)
        self.r.update(ds=0x4a06, cs=0x161d, ip=8)

    def library(self, segment, offset):
        # LTGOLD call-site mappings: shared string helpers and vector free().
        if segment: return False
        return super().library(0, 0x1baa if offset == 0x2d5e else offset - 0x26ad)


def lua_value(value):
    if value is None:return 'nil'
    if isinstance(value,bool):return 'true' if value else 'false'
    if isinstance(value,dict):return '{'+','.join('['+lua_value(int(k) if k.isdigit() else k)+']='+lua_value(v) for k,v in value.items())+'}'
    if isinstance(value,list):return '{'+','.join(lua_value(v) for v in value)+'}'
    if isinstance(value,str):return '"'+''.join('\\%03d'%b for b in value.encode('cp866'))+'"'
    return str(value)


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--cases',type=int,default=300)
    ap.add_argument('--target',choices=['ltpro','ltgold'],default='ltpro');args=ap.parse_args()
    image=Path('LTGOLD/'+args.target.upper()+'.EXE').read_bytes()
    # Input records include the actual boundary nodes; values are native byte fields.
    def fixture(tags):return [{'12':ord(c),'text':''} for c in '*'+tags+'*']
    table=0x54b4a if args.target=='ltgold' else 0x2a740
    header=struct.unpack_from('<H',image,8)[0]*16
    patterns=[]
    for i in range(56):
        offset,segment=struct.unpack_from('<HH',image,table+i*10)
        address=header+segment*16+offset
        patterns.append(image[address:image.index(0,address)].decode('ascii'))
    patterns+=['NTN','N N']
    cases=[fixture(p) for p in patterns]
    rng=random.Random(1993)
    for _ in range(args.cases):
        f=fixture(rng.choice(patterns))
        for row in f[1:-1]:
            row.update({'15':rng.choice([0,0,ord('w'),ord('g'),ord('/'),ord('%'),ord('='),ord('r'),ord('a')]),
                        '102':rng.choice([0,ord('E')]),'114':rng.choice([0,1]),'118':rng.choice([0,2]),
                        'text':rng.choice(['','P','-','мес)'])})
        cases.append(f)
    # Every extracted reorder action is non-null; A-N points to an empty string.
    # DOS interrupt vectors and startup state are outside this isolated call harness.
    expected=[];steps=0;cache={}
    for f in cases:
        machine=(GoldMachine if args.target=='ltgold' else Machine)(image)
        machine.cache=cache;expected.append(machine.fixture(f));steps+=machine.steps
    with tempfile.TemporaryDirectory(prefix='ltpro-native-') as directory:
        fixture_path=Path(directory)/'cases.lua';fixture_path.write_text('return '+lua_value(cases))
        output=subprocess.check_output(['lua','tools/ltpro_native_probe.lua',str(fixture_path)],text=True)
    actual=[json.loads(line) for line in output.splitlines()]
    assert len(actual)==len(expected)
    differences=[(i,a,b) for i,(a,b) in enumerate(zip(expected,actual)) if list(a)!=b]
    for i,a,b in differences[:10]:print('DIFF',i,cases[i],'EXE',a,'Lua',b)
    print(f'{args.target.upper()} 8086 reorder vs Lua: {len(cases)-len(differences)}/{len(cases)} cases; {steps} instructions')
    raise SystemExit(bool(differences))

if __name__=='__main__':main()
