#!/usr/bin/env python3
import curses,sys,argparse,struct

K={'q':'Quit','h':'Hex','t':'Text','o':'Offset','x':'Pointers','/':'Search','1-9':'Columns','PgUp/Dn':'Page'}
F,d,s,data,w,a=set(),b'',None,None,0,None
pg,cur,hx,tx,of,pr,gs=0,0,1,1,1,0,4
sr=None
mg=0x4a06
ofs=8

def S(h):return h-2
def P(h):return h-3
def B():return a.width if hx else w-1
def cx():return cur%B()
def cy():return(cur-pg)//B()
def sb(tl,fl,h):
	bh,x=h-3,w-1
	if bh<3:return
	hp=int(min(max(fl/max(tl-bh,1),0),1)*(bh-1))
	for i in range(bh):s.addstr(i,x,"█"if i==hp else"▒",curses.color_pair(1))
def to_enc(b,e):
	try:ch=bytes([b]).decode(e);return ch if ch.isprintable()else"."
	except:return"."
def ptr(p,c):
	try:return struct.unpack_from("<H",d,p+c)[0]
	except:return 9999999
def st():
	v,t=0,[]
	t.append(f"PAGE {pg:06X}/{len(d):06X}")
	t.append(f"CURS {cur:06X}")
	if ptr(pg,cy()*B()+cx())<len(d):
		v=ptr(pg,cy()*B()+cx())
		t.append(f"VAL {v:04X}")
		t.append(f"PTR {"".join(to_enc(c,a.enc)for c in d[v:v+16])}")
	return t
def inl(hb,pt):
	for n in range(B()):
		# if n+pt in F:continue
		for m in range(-1,3):
			if ptr(pt,n+m) == mg:
				v,k=ptr(pt,n+m-2),(2-m)*2
				hb[n]="".join(to_enc(c,a.enc) for c in d[v+k:v+k+2]); continue

def dl(pt,r,highlight):
	global w
	if pt>=len(d):return
	hb=[f"{b:02X}"for b in d[pt:pt+B()]]
	inl(hb,pt) if pr else None
	sel,std,ln=set(),set(),str()
	if hx and of:ln+=f"{pt:06X}  ";assert(len(ln)==ofs)
	if hx:
		def mark(sel,pos):
			for k in range(2):sel.add(pos*2+(pos//gs)+len(ln)+k)
		for k in range(B()):
			if pt+k in F:mark(std,k)
		if highlight:mark(sel,cx())
		groups=["".join(hb[i:i+gs])for i in range(0,len(hb),gs)]
		ln+=" ".join(groups)+"  "
	if tx:
		if highlight:sel.add(cx()+len(ln))
		ln+="".join(to_enc(c,a.enc)for c in d[pt:pt+B()])
	try:
		for i,ch in enumerate(ln[:w-1]):
			attr=curses.color_pair(1)
			if i in std:attr=curses.color_pair(2)
			if highlight and i in sel:attr=curses.color_pair(6)
			data.addstr(r,i,ch,attr)
	except curses.error:pass
def dh():
	for n in range(w):s.addstr(0,n,' ',curses.color_pair(4))
	s.addstr(0,0," ".join(st())[:w],curses.color_pair(4))
def dk():
	p=0
	try:s.addstr(s.getmaxyx()[0]-1,0," "*w,curses.color_pair(7))
	except:pass
	try:
		if sr is not None: s.addstr(s.getmaxyx()[0]-1,0,f"Find: {sr} ({len(F)//max(1,len(sr)//2)} found)",curses.color_pair(7));return
		for k,v in K.items():s.addstr(s.getmaxyx()[0]-1,p,f' {k}',curses.color_pair(7));s.addstr(s.getmaxyx()[0]-1,p+len(k)+1,f'{v} ',curses.color_pair(4));p+=len(k)+len(v)+2
	except:pass
def vis(h):
	global cur, pg
	if cur<pg:pg=(cur//B()-1)*B();redraw()
	if cur>pg+S(h)*B():pg=(cur//B()-S(h)+1)*B();redraw()
	return cur
def redraw():
	h=s.getmaxyx()[0]
	data.clear()
	for r in range(S(h)):dl(pg+r*B(),r,r==cy())
	dh();dk();sb((len(d)+B()-1)//B(),pg//B(),h);s.refresh();data.refresh()
def main(scr,args):
	global s,data,w,a,d,pg,cur,hx,tx,of,pr,gs,sr,F
	s,a=scr,args
	with open(a.file,"rb")as f:d=f.read()[a.start:a.end]
	for i in range(len(d)-1):
		if a.find16 and struct.unpack_from("<H",d,i)[0]==a.find16:F.add(i);F.add(i+1)
		if a.find8 and struct.unpack_from("<B",d,i)[0]==a.find8:F.add(i)
	curses.mousemask(curses.ALL_MOUSE_EVENTS);curses.curs_set(0);curses.start_color();curses.use_default_colors()
	curses.use_default_colors()
	curses.init_pair(1,curses.COLOR_CYAN,curses.COLOR_BLUE)
	curses.init_pair(2,curses.COLOR_BLUE,curses.COLOR_YELLOW)
	curses.init_pair(3,curses.COLOR_WHITE,curses.COLOR_BLUE)
	curses.init_pair(4,curses.COLOR_BLACK,curses.COLOR_CYAN)
	curses.init_pair(5,curses.COLOR_BLACK,curses.COLOR_WHITE)
	curses.init_pair(6,curses.COLOR_BLACK,curses.COLOR_CYAN)
	curses.init_pair(7,curses.COLOR_WHITE,curses.COLOR_BLACK)
	h,w=s.getmaxyx()
	data=s.subwin(h-1,w-1,1,0)
	data.scrollok(True)
	data.bkgd(' ',curses.color_pair(3))
	s.bkgd(' ',curses.color_pair(3))
	hx,tx,of,pr,gs=a.no_hex^1,a.no_text^1,a.no_line^1,0,a.group
	redraw()
	while 1:
		h,w=s.getmaxyx();mp=max(0,len(d)-B());tl=(len(d)+B()-1)//B()
		c=s.getch()
		if sr is not None:
			if c == 27: sr=None; F.clear(); redraw()
			else:
				if c == 10 or c == 13: 
					oc = sorted(list(F))
					srt = [v for v in oc if v >= cur+len(sr)//2]
					if not oc: pass
					elif srt: cur = srt[0]
					else: cur = oc[0]
					pg=max(0,(cur//B())*B()-h//2*B())
				elif c == curses.KEY_BACKSPACE or c == 127: sr = sr[:-1] if sr else sr
				elif 32 <= c <= 126: sr += chr(c)
				F.clear()
				try:
					value = int(sr,16)
					for i in range(len(d)-1):
						if len(sr) <= 2 and struct.unpack_from(">B",d,i)[0]==value:[F.add(i+n) for n in range(1)]
						if len(sr) <= 4 and struct.unpack_from(">H",d,i)[0]==value:[F.add(i+n) for n in range(2)]
						if len(sr) <= 8 and struct.unpack_from(">I",d,i)[0]==value:[F.add(i+n) for n in range(4)]
				except: pass
				redraw()
		elif c in(ord('q'),27):break
		elif c==curses.KEY_DOWN:
			if vis(h)+B()<len(d):
				dl(pg+cy()*B(),cy(),False)
				cur+=B()
				if cy()>=S(h):pg=min(pg+B(),mp);data.scroll(1);dl(pg+S(h)*B(),h-1,False)
				dl(pg+cy()*B(),cy(),True)
		elif c==curses.KEY_UP:
			if vis(h)>=B():
				dl(pg+cy()*B(),cy(),False)
				cur-=B()
				if cy()<0:pg=max(pg-B(),0);data.scroll(-1);dl(pg,0,False)
				dl(pg+cy()*B(),cy(),True)
		elif c==curses.KEY_LEFT:
			if vis(h)>0:
				lcy,cur=cy(),cur-1
				if cy()!=lcy:dl(pg+lcy*B(),lcy,False)
				dl(pg+cy()*B(),cy(),True)
		elif c==curses.KEY_RIGHT:
			if vis(h)<len(d)-1:
				lcy,cur=cy(),cur+1
				if cy()!=lcy:dl(pg+lcy*B(),lcy,False)
				dl(pg+cy()*B(),cy(),True)
		elif c>ord('0') and c<=ord('9'):a.width = (c-ord('0'))*4;redraw()
		elif c==curses.KEY_NPAGE:vis(h);pg=min(pg+P(h)*B(),mp);cur=min(cur+P(h)*B(),mp);redraw()
		elif c==curses.KEY_PPAGE:vis(h);pg=max(pg-P(h)*B(),0);cur=max(cur-P(h)*B(),0);redraw()
		elif c==ord('h'):hx=not hx;vis(h);redraw()
		elif c==ord('t'):tx=not tx;redraw()
		elif c==ord('o'):of=not of;redraw()
		elif c==ord('x'):pr=not pr;redraw()
		elif c==ord('/'):sr="";redraw()
		elif c==curses.KEY_MOUSE:
			try:_,mx,my,_,bs=curses.getmouse()
			except:continue
			if not hx:
				if my>0 and mx<B():cur = mx+(my-1)*B();redraw()
			else:
				width = B()*2+B()//gs
				if of: mx-=ofs
				if mx>width:cur=mx-width-1+(my-1)*B()+pg;redraw()
				elif mx>=0 and mx < width:mx-=mx//(gs*2+1);cur=mx//2+(my-1)*B()+pg;redraw()

			if bs&curses.BUTTON4_PRESSED and pg>0:pg=max(pg-B(),0);data.scroll(-1);dl(pg,0,False)
			elif mx==w-1 and 1<=my<h-1:pg=min(int(min(max((my-1)/(h-4),0),1)*(tl-1))*B(),mp);cur=pg;redraw()
		
		dh();sb(tl,pg//B(),h);dk();s.refresh();data.refresh()

if __name__=="__main__":
	p=argparse.ArgumentParser(description="Hex/text dump with grouping and encoding")
	p.add_argument("file",help="binary file to dump")
	p.add_argument("--width",type=int,default=16,help="bytes per line (default: 16)")
	p.add_argument("--group",type=int,default=4,help="group bytes visually (default: 4)")
	p.add_argument("--enc",default="cp866",help="text encoding for right column (default: cp866)")
	p.add_argument("--no-line",action="store_true",help="disable line numbers")
	p.add_argument("--no-hex",action="store_true",help="disable hex output")
	p.add_argument("--no-text",action="store_true",help="disable text output")
	p.add_argument('--start',type=int,default=0,help='Start position in hex (default: 0)')
	p.add_argument('--end',type=int,default=-1,help='End position in hex (exclusive, default: end of file)')
	p.add_argument('--find8',type=lambda s:int(s,16),default=None,help='Highlight all instances of a 8-bit number')
	p.add_argument('--find16',type=lambda s:int(s,16),default=None,help='Highlight all instances of a 16-bit number')
	p.add_argument('--find32',type=lambda s:int(s,16),default=None,help='Highlight all instances of a 32-bit number')
	a=p.parse_args()
	curses.wrapper(main,a)