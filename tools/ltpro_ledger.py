#!/usr/bin/env python3
"""Inventory recovered dispatch selectors, aliases, rule references and local CFGs.

Candidate ES-relative fields require context before being called node fields. This
is a bounded static inventory, never a claim of whole-program reachability.
"""
import collections
import json
import re
import struct
from pathlib import Path
from capstone import Cs,CS_ARCH_X86,CS_MODE_16
from capstone.x86 import X86_OP_IMM,X86_OP_MEM
from ltpro_capture import digest

FAMILIES={
    'T1':(0x11BF0,0x1254A,0x2738C,47,10),
    'T2':(0x11BF0,0x13700,0x2756C,157,10),
    'T3':(0x11BF0,0x142F0,0x27B98,136,10),
    'T4':(0x142F0,0x16190,0x2952C,178,9),
    'reorder':(0x16190,0x167C0,0x2A740,56,10),
    'cleanup':(0x167C0,0x16B3E,0x2AB30,9,10),
    'T7':(0x17E90,0x18CD0,0x2AC92,35,8),
    'T7_select':(0x17E90,0x18CD0,None,0,8),
    'T8':(0x1D260,0x1FD90,0x2B134,83,8),
}

def cfg(image,start,lower,upper):
    md=Cs(CS_ARCH_X86,CS_MODE_16);md.detail=True
    pending=[start];seen=set();calls=set();fields=collections.defaultdict(set);indirect=[]
    escapes=set();limit=False
    while pending:
        at=pending.pop()
        while lower<=at<upper and at not in seen:
            if len(seen)>=2048: limit=True;pending=[];break
            instruction=next(md.disasm(image[at:at+16],at,count=1),None)
            if instruction is None: escapes.add(at);break
            seen.add(at);following=at+instruction.size
            for operand in instruction.operands:
                if operand.type==X86_OP_MEM and instruction.reg_name(operand.mem.segment)=='es':
                    fields[operand.mem.disp].add(instruction.mnemonic)
            if instruction.mnemonic=='lcall' and all(o.type==X86_OP_IMM for o in instruction.operands):
                segment,offset=(o.imm for o in instruction.operands)
                calls.add(0x3A00+segment*16+offset)
            elif instruction.mnemonic=='call' and instruction.operands[0].type==X86_OP_IMM:
                calls.add(instruction.operands[0].imm)
            if instruction.mnemonic.startswith('ret'):break
            if instruction.mnemonic.startswith('j') or instruction.mnemonic=='loop':
                operand=instruction.operands[0]
                if operand.type!=X86_OP_IMM:
                    indirect.append(at);break
                target=operand.imm
                if lower<=target<upper:pending.append(target)
                else:escapes.add(target)
                if instruction.mnemonic=='jmp':break
            at=following
        if at<lower or at>=upper:escapes.add(at)
    return {'instructions_visited':len(seen),'called_addresses':sorted(calls),
        'candidate_es_relative_fields':[{'offset':offset,'operations':sorted(ops)} for offset,ops in sorted(fields.items())],
        'indirect_transfers':sorted(set(indirect)),'range_exits':sorted(escapes),'instruction_limit_hit':limit}

def main():
    image=Path('LTGOLD/LTPRO.EXE').read_bytes()
    stages=json.loads(Path('test/ltpro/stages.json').read_text())
    events=[(case['id'],stage) for case in stages['cases'] for stage in case['snapshots'] if stage['stage']=='T1-match']
    source=Path('core/ltpro/dispatch.lua').read_text()
    families=[];all_targets=set();selector_count=0
    for name,body in re.findall(r'\["([^"\n]+)"\] = \{(.*?)\n  \},',source,re.S):
        lower,upper,table,count,size=FAMILIES[name]
        default=int(re.search(r'default = (0x[0-9A-F]+)',body)[1],16)
        selectors=[(int(key),int(value,16)) for key,value in re.findall(r'\[(\d+)\] = (0x[0-9A-F]+)',body)]
        references=collections.defaultdict(list)
        if table:
            for index in range(count):
                at=table+index*size
                flag=image[at+8] if size==9 else struct.unpack_from('<H',image,at+6 if size==8 else at+8)[0]
                references[flag].append(index+1)
        aliases=collections.defaultdict(list)
        for selector,address in selectors:aliases[address].append(selector)
        rows=[]
        for selector,address in selectors:
            status='unported handler'
            if name=='T1': status='implemented; controlled-node instruction coverage; branch coverage incomplete'
            elif name=='cleanup' and selector in (1,8,11): status='implemented; question-stage coverage only'
            elif name=='T7_select': status='class selection port; production integration pending'
            observed=[case for case,event in events if name=='T1' and event['handler']==selector]
            rows.append({'selector':selector,'address':address,'aliases_at_address':aliases[address],
                'is_default_target':address==default,'grammar_records':references[selector],
                'port_status':status,'native_T1_observations':observed})
        selector_count+=len(selectors);all_targets.update(address for _,address in selectors)
        all_targets.add(default)
        families.append({'family':name,'default_address':default,'selectors':rows,
            'blocks':[dict(address=address,**cfg(image,address,lower,upper)) for address in sorted(set(aliases)|{default})]})
    result={'schema':1,'executable_sha256':digest(image),'stages_sha256':digest(Path('test/ltpro/stages.json').read_bytes()),
        'selector_count':selector_count,'distinct_target_addresses_including_defaults':len(all_targets),
        'scope':'Bounded intraprocedural static CFG inventory; no liveness or whole-program equivalence claim.',
        'families':families}
    Path('reference/LTPRO_ROUTINE_LEDGER.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f'Ledger: {selector_count} selectors, {len(all_targets)} distinct targets; {len(events)} native T1 match events')

if __name__=='__main__':main()
