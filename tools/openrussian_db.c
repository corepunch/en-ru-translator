#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <iconv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define HEADER_SIZE 40u
#define EMPTY_SLOT UINT32_MAX

typedef struct { unsigned char *key, *value; size_t key_len, value_len, sequence; } Record;
typedef struct { Record *items; size_t count, capacity; } Records;
typedef struct { char **items; size_t count; } Fields;
typedef struct { unsigned char pos, *data; size_t length; uint64_t hash; } Pattern;
typedef struct { Pattern *items; size_t count, capacity; } Patterns;

static void fail(const char *message) { fprintf(stderr, "openrussian_db: %s\n", message); exit(1); }
static void *allocate(size_t size) { void *p = malloc(size ? size : 1); if (!p) fail("out of memory"); return p; }
static size_t next_sequence;
static size_t unrepresentable_codepoints;
static Patterns morphology_patterns;
static void put16(unsigned char *p, uint16_t v) { p[0]=(unsigned char)v; p[1]=(unsigned char)(v>>8); }
static void put32(unsigned char *p, uint32_t v) { p[0]=(unsigned char)v; p[1]=(unsigned char)(v>>8); p[2]=(unsigned char)(v>>16); p[3]=(unsigned char)(v>>24); }
static uint32_t get32(const unsigned char *p) { return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24; }

static unsigned char *convert_encoding(const char *from, const char *to, const unsigned char *input, size_t input_len, size_t *output_len) {
  iconv_t cd=iconv_open(to,from); if (cd==(iconv_t)-1) fail("iconv_open failed");
  size_t capacity=input_len*4+32, left=input_len, out_left=capacity;
  unsigned char *output=allocate(capacity), *out=output; char *in=(char *)input;
  size_t converted=iconv(cd,&in,&left,(char **)&out,&out_left);
  if (converted==(size_t)-1 || left) {
    fprintf(stderr,"openrussian_db: conversion %s -> %s failed at input byte %zu (remaining %zu bytes):",from,to,input_len-left,left);
    for(size_t i=0;i<left&&i<8;i++)fprintf(stderr," %02x",(unsigned char)in[i]);
    fputc('\n',stderr);iconv_close(cd);free(output);fail("input cannot be converted to requested encoding");
  }
  *output_len=capacity-out_left; iconv_close(cd); return output;
}

static unsigned char *to_cp866(const char *text, size_t *length) {
  size_t source_len=strlen(text),normalized_len=0;
  unsigned char *normalized=allocate(source_len+1);
  for(size_t i=0;i<source_len;i++) {
    if((unsigned char)text[i]==0xd1&&(unsigned char)text[i+1]==0x91) {
      normalized[normalized_len++]=0xd0;normalized[normalized_len++]=0xb5;i++;
    } else if((unsigned char)text[i]==0xd0&&(unsigned char)text[i+1]==0x81) {
      normalized[normalized_len++]=0xd0;normalized[normalized_len++]=0x95;i++;
    } else if((unsigned char)text[i]==0xcc&&((unsigned char)text[i+1]>=0x80&&(unsigned char)text[i+1]<=0x8f)) {
      /* OpenRussian marks stress with combining accents. Keep the base letter;
       * the untouched UTF-8 source TSV remains the lossless archive. */
      i++;
    } else normalized[normalized_len++]=(unsigned char)text[i];
  }
  normalized[normalized_len]=0;
  iconv_t cd=iconv_open("CP866//TRANSLIT","UTF-8");if(cd==(iconv_t)-1)fail("iconv_open failed");
  size_t capacity=normalized_len*4+32,out_left=capacity,at=0;unsigned char *result=allocate(capacity),*out=result;
  while(at<normalized_len) {
    size_t width=(normalized[at]&0x80)==0?1:(normalized[at]&0xe0)==0xc0?2:(normalized[at]&0xf0)==0xe0?3:4;
    if(at+width>normalized_len)width=normalized_len-at;
    char *in=(char *)normalized+at;size_t left=width;
    if(iconv(cd,&in,&left,(char **)&out,&out_left)==(size_t)-1||left) {
      iconv(cd,NULL,NULL,(char **)&out,&out_left);if(!out_left)fail("CP866 output buffer exhausted");*out++='?';out_left--;unrepresentable_codepoints++;at+=width;
    } else at+=width;
  }
  *length=capacity-out_left;iconv_close(cd);free(normalized);
  /* Retain the runtime's one-byte mapping if an unnormalized lowercase ё remains. */
  for(size_t i=0;i<*length;i++)if(result[i]==0xf1)result[i]=0xf0;
  return result;
}
static char *from_cp866(const unsigned char *text,size_t length) {
  size_t out_len; unsigned char *out=convert_encoding("CP866","UTF-8",text,length,&out_len);
  char *result=allocate(out_len+1); memcpy(result,out,out_len); result[out_len]=0; free(out); return result;
}
static unsigned char fold(unsigned char c) {
  if(c>='A'&&c<='Z') return c+32;
  if(c>=0x80&&c<=0x8f) return c+0x20;
  if(c>=0x90&&c<=0x9f) return c+0x50;
  if(c==0xf0) return 0xf1;
  return c;
}
static int record_compare(const void *left,const void *right) {
  const Record *a=left,*b=right; size_t n=a->key_len<b->key_len?a->key_len:b->key_len;
  for(size_t i=0;i<n;i++){ unsigned char x=fold(a->key[i]),y=fold(b->key[i]); if(x!=y)return x<y?-1:1; }
  if(a->key_len!=b->key_len)return a->key_len<b->key_len?-1:1;
  return a->sequence==b->sequence?0:(a->sequence<b->sequence?-1:1);
}
static void add_record(Records *db,const unsigned char *key,size_t key_len,const unsigned char *value,size_t value_len) {
  if(memchr(key,'*',key_len)||memchr(key,'\n',key_len)||memchr(value,'\n',value_len)) fail("record contains a reserved delimiter");
  if(db->count==db->capacity){db->capacity=db->capacity?db->capacity*2:128;db->items=realloc(db->items,db->capacity*sizeof(Record));if(!db->items)fail("out of memory");}
  Record *r=&db->items[db->count++]; r->key=allocate(key_len);memcpy(r->key,key,key_len);r->key_len=key_len;
  r->value=allocate(value_len);memcpy(r->value,value,value_len);r->value_len=value_len;r->sequence=next_sequence++;
}
static void add_utf8_record(Records *db,const char *key,const char *value) {
  size_t key_len,value_len;unsigned char *encoded_key=to_cp866(key,&key_len),*encoded_value=to_cp866(value,&value_len);
  add_record(db,encoded_key,key_len,encoded_value,value_len);free(encoded_key);free(encoded_value);
}
static Fields parse_tsv(char *line) {
  Fields result={0}; size_t cap=0; char *field=allocate(strlen(line)+1),*out=field; int quoted=0;
  for(char *p=line;;p++) {
    char c=*p;
    if(quoted) { if(c=='"'&&p[1]=='"'){*out++='"';p++;} else if(c=='"')quoted=0; else if(!c)fail("unterminated quoted TSV field"); else *out++=c; }
    else if(c=='"'&&out==field)quoted=1;
    else if(c=='\t'||c==0||c=='\r'||c=='\n') {
      *out=0; if(result.count==cap){cap=cap?cap*2:16;result.items=realloc(result.items,cap*sizeof(char *));if(!result.items)fail("out of memory");}
      result.items[result.count++]=field;
      if(c==0||c=='\r'||c=='\n')break;
      field=allocate(strlen(line)+1);out=field;
    } else *out++=c;
  }
  return result;
}
static size_t column(Fields *header,const char *name) { for(size_t i=0;i<header->count;i++)if(!strcmp(header->items[i],name))return i; return (size_t)-1; }
static const char *cell(Fields *row,size_t at) { return at<row->count?row->items[at]:""; }
static void lower_ascii(char *text) { for(;*text;text++)if(*text>='A'&&*text<='Z')*text=(char)(*text+32); }
static int is_empty(const char *s) { return !s||!*s; }

static void add_english_alias(Records *dic,const char *alias,const char *pos,const char *lemma,const char *aspect,int plural) {
  /* OpenRussian's `others` table includes fixed expressions. Emit those as
   * literal phrase readings; they do not have an inflectional POS adapter. */
  if(!strcmp(pos,"other")) {
    size_t alias_len,lemma_len;unsigned char *key=to_cp866(alias,&alias_len),*lemma_bytes=to_cp866(lemma,&lemma_len);
    unsigned char *value=allocate(lemma_len+4);value[0]='W';value[1]='#';memcpy(value+2,lemma_bytes,lemma_len);value[lemma_len+2]='#';
    add_record(dic,key,alias_len,value,lemma_len+3);free(key);free(lemma_bytes);free(value);return;
  }
  const char *russian_lemma=plural&&!strcmp(pos,"noun")&&!strcmp(alias,"people")&&!strcmp(lemma,"человек")?"люди":lemma;
  size_t lemma_len; unsigned char *encoded=to_cp866(russian_lemma,&lemma_len);
  unsigned char *value=allocate(lemma_len+8); size_t used=0;
  if(!strcmp(pos,"noun")){value[used++]=plural?'n':'N';}
  else if(!strcmp(pos,"verb")){value[used++]='e';value[used++]='0';value[used++]=!strcmp(aspect,"perfective")?'1':'0';}
  else value[used++]='A';
  memcpy(value+used,encoded,lemma_len);used+=lemma_len;
  size_t alias_len; unsigned char *key=to_cp866(alias,&alias_len);add_record(dic,key,alias_len,value,used);
  free(encoded);free(value);free(key);
}
static void parse_glosses(Records *dic,const char *gloss,const char *pos,const char *lemma,const char *aspect) {
  char *copy=strdup(gloss); if(!copy)fail("out of memory");
  char *group_save=NULL;
  for(char *group=strtok_r(copy,";",&group_save);group;group=strtok_r(NULL,";",&group_save)) {
    char *alias_save=NULL;
    for(char *alias=strtok_r(group,",",&alias_save);alias;alias=strtok_r(NULL,",",&alias_save)) {
      while(*alias==' '||*alias=='\t')alias++; size_t n=strlen(alias);while(n&&(alias[n-1]==' '||alias[n-1]=='\t'))alias[--n]=0;
      while(n&&strchr(".!?;:",alias[n-1]))alias[--n]=0;
      if(!n)continue; lower_ascii(alias);
      int plural=!strcmp(pos,"noun")&&(!strcmp(alias,"people")||!strcmp(alias,"children"));
      add_english_alias(dic,alias,pos,lemma,aspect,plural);
      if(!strcmp(pos,"noun")&&!strcmp(lemma,"ребёнок")&&!strcmp(alias,"child"))
        add_english_alias(dic,"children",pos,lemma,aspect,1);
    }
  }
  free(copy);
}

static void add_russian_lexeme(Records *rus,const char *pos,const char *lemma,const char *gender,const char *sg_only,const char *pl_only) {
  size_t n; unsigned char *encoded=to_cp866(lemma,&n), value[5]; size_t used=0;
  if(!strcmp(pos,"noun")) {
    value[used++]='N';value[used++]=0xc0;
    /* Keep the legacy RUS number bits beside the 2-bit gender code. */
    int g=!strcmp(gender,"m")?1:!strcmp(gender,"f")?2:0;
    value[used++]=(unsigned char)(0x80|g|(!strcmp(pl_only,"1")?0x08:0)|(!strcmp(sg_only,"1")?0x04:0));
    value[used++]=0;
  } else if(!strcmp(pos,"verb")) { value[used++]='V';value[used++]=0xc0;value[used++]=0x88;value[used++]=0;value[used++]=0; }
  else { value[used++]='A';value[used++]=0xc0;value[used++]=0;value[used++]=0; }
  for(size_t i=0;i<rus->count;i++)if(rus->items[i].key_len==n&&!memcmp(rus->items[i].key,encoded,n)&&rus->items[i].value_len&&rus->items[i].value[0]==value[0]){free(encoded);return;}
  add_record(rus,encoded,n,value,used);free(encoded);
}

static uint64_t pattern_hash(unsigned char pos,const unsigned char *data,size_t length) {
  uint64_t h=1469598103934665603ULL; h=(h^pos)*1099511628211ULL;
  for(size_t i=0;i<length;i++)h=(h^data[i])*1099511628211ULL;
  return h;
}
static uint16_t intern_pattern(unsigned char pos,const unsigned char *data,size_t length) {
  uint64_t hash=pattern_hash(pos,data,length);
  for(size_t i=0;i<morphology_patterns.count;i++) {
    Pattern *p=&morphology_patterns.items[i];
    if(p->hash==hash&&p->pos==pos&&p->length==length&&!memcmp(p->data,data,length))return (uint16_t)i;
  }
  if(morphology_patterns.count>=UINT16_MAX)fail("too many distinct morphology patterns");
  if(morphology_patterns.count==morphology_patterns.capacity) {
    morphology_patterns.capacity=morphology_patterns.capacity?morphology_patterns.capacity*2:128;
    morphology_patterns.items=realloc(morphology_patterns.items,morphology_patterns.capacity*sizeof(Pattern));
    if(!morphology_patterns.items)fail("out of memory");
  }
  size_t id=morphology_patterns.count++; Pattern *p=&morphology_patterns.items[id];
  p->pos=pos;p->data=allocate(length);memcpy(p->data,data,length);p->length=length;p->hash=hash;
  return (uint16_t)id;
}

static void add_forms(Records *morph,Fields *header,Fields *row,const char *pos,const char *lemma,const char *aspect) {
  if(!strcmp(pos,"other"))return;
  static const char *noun_slots[]={"sg_nom","sg_gen","sg_dat","sg_acc","sg_inst","sg_prep","pl_nom","pl_gen","pl_dat","pl_acc","pl_inst","pl_prep"};
  static const char *verb_slots[]={"imperative_sg","imperative_pl","past_m","past_f","past_n","past_pl","presfut_sg1","presfut_sg2","presfut_sg3","presfut_pl1","presfut_pl2","presfut_pl3"};
  static const char *adj_slots[]={"decl_m_nom","decl_m_gen","decl_m_dat","decl_m_acc","decl_m_inst","decl_m_prep","decl_f_nom","decl_f_gen","decl_f_dat","decl_f_acc","decl_f_inst","decl_f_prep","decl_n_nom","decl_n_gen","decl_n_dat","decl_n_acc","decl_n_inst","decl_n_prep","decl_pl_nom","decl_pl_gen","decl_pl_dat","decl_pl_acc","decl_pl_inst","decl_pl_prep","comparative","superlative","short_m","short_f","short_n","short_pl"};
  const char **slots=!strcmp(pos,"noun")?noun_slots:!strcmp(pos,"verb")?verb_slots:adj_slots;
  size_t count=!strcmp(pos,"noun")?sizeof noun_slots/sizeof *noun_slots:!strcmp(pos,"verb")?sizeof verb_slots/sizeof *verb_slots:sizeof adj_slots/sizeof *adj_slots;
  /* Each source form is stored as a one-byte trim count plus its CP866 suffix.
   * Identical complete slot maps share one table record. */
  size_t lemma_len;unsigned char *encoded_lemma=to_cp866(lemma,&lemma_len);
  size_t cap=1;for(size_t i=0;i<count;i++)cap+=1+3*strlen(cell(row,column(header,slots[i])));
  unsigned char *pattern=allocate(cap);size_t used=0;
  for(size_t i=0;i<count;i++) {
    const char *source=cell(row,column(header,slots[i]));char *copy=strdup(source);if(!copy)fail("out of memory");
    unsigned char *cuts=allocate(strlen(source)+2),**suffixes=allocate((strlen(source)+2)*sizeof(unsigned char *));
    size_t *suffix_lengths=allocate((strlen(source)+2)*sizeof(size_t)),variants=0;char *save=NULL;
    for(char *form=strtok_r(copy,",",&save);form;form=strtok_r(NULL,",",&save)) {
      while(*form==' '||*form=='\t')form++;size_t n=strlen(form);while(n&&(form[n-1]==' '||form[n-1]=='\t'))form[--n]=0;
      for(size_t j=0;j<n;j++)if(form[j]=='\''){memmove(form+j,form+j+1,n-j);n--;j--;}
      if(!n)continue;
      size_t form_len;unsigned char *encoded_form=to_cp866(form,&form_len);size_t common=0;
      while(common<lemma_len&&common<form_len&&encoded_lemma[common]==encoded_form[common])common++;
      size_t cut=lemma_len-common,suffix_len=form_len-common;
      if(cut>255||suffix_len>255||variants>=255)fail("morphology transform exceeds compact byte limits");
      cuts[variants]=(unsigned char)cut;suffixes[variants]=allocate(suffix_len);memcpy(suffixes[variants],encoded_form+common,suffix_len);suffix_lengths[variants]=suffix_len;variants++;free(encoded_form);
    }
    if(variants>255)fail("too many form variants in one slot");
    pattern[used++]=(unsigned char)variants;
    for(size_t j=0;j<variants;j++) {
      pattern[used++]=cuts[j];pattern[used++]=(unsigned char)suffix_lengths[j];
      memcpy(pattern+used,suffixes[j],suffix_lengths[j]);used+=suffix_lengths[j];free(suffixes[j]);
    }
    free(cuts);free(suffixes);free(suffix_lengths);free(copy);
  }
  uint16_t id=intern_pattern(!strcmp(pos,"noun")?'n':!strcmp(pos,"verb")?'v':'a',pattern,used);
  /* This reference is deliberately separate from the native POS code. The
   * verb generator still receives its imperative flag and selects slots 0/1. */
  unsigned char value[8];value[0]='M';value[1]=!strcmp(pos,"noun")?'n':!strcmp(pos,"verb")?'v':'a';
  value[2]=!strcmp(pos,"verb")?(!strcmp(aspect,"perfective")?'1':'0'):'0';
  snprintf((char *)value+3,5,"%04X",id);
  add_record(morph,encoded_lemma,lemma_len,value,7);free(encoded_lemma);free(pattern);
}

static void import_file(Records *source_dic,Records *source_rus,Records *morph,const char *path,const char *pos) {
  FILE *file=fopen(path,"r");if(!file){perror(path);exit(1);}char *line=NULL;size_t cap=0;ssize_t n=getline(&line,&cap,file);if(n<0)fail("empty source TSV");
  Fields header=parse_tsv(line);size_t bare=column(&header,"bare"), gloss=column(&header,"translations_en"), gender=column(&header,"gender"), aspect=column(&header,"aspect"), sg_only=column(&header,"sg_only"), pl_only=column(&header,"pl_only"), source_row=column(&header,"source_row");
  if(bare==(size_t)-1||gloss==(size_t)-1||source_row==(size_t)-1)fail("source TSV is missing required columns");
  while((n=getline(&line,&cap,file))>=0) {
    if(line[0]=='#'||line[0]=='\n')continue;Fields row=parse_tsv(line);const char *lemma=cell(&row,bare),*english=cell(&row,gloss),*g=cell(&row,gender),*a=cell(&row,aspect);
    if(is_empty(lemma))continue;
    if(is_empty(cell(&row,source_row)))fail("OpenRussian row is missing source_row id");
    if(strcmp(pos,"other"))add_russian_lexeme(source_rus,pos,lemma,g,cell(&row,sg_only),cell(&row,pl_only));
    if(!is_empty(english))parse_glosses(source_dic,english,pos,lemma,a);
    add_forms(morph,&header,&row,pos,lemma,a);
  }
  free(line);fclose(file);
}

static void add_people_plural(Records *rus) {
  /* LTPRO stores this suppletive plural as its own noun, paradigm 30. */
  static const unsigned char key[]={0xab,0xee,0xa4,0xa8}; /* люди */
  static const unsigned char code[]={'N',0xd2,0x88,0x9e};
  add_record(rus,key,sizeof key,code,sizeof code);
}

static void emit_morphology_patterns(Records *rus) {
  for(size_t i=0;i<morphology_patterns.count;i++) {
    Pattern *p=&morphology_patterns.items[i];char key[16];
    int n=snprintf(key,sizeof key,"@M%05zu",i);if(n<0||(size_t)n>=sizeof key)fail("morphology pattern key overflow");
    unsigned char *value=allocate(p->length*2+1);size_t used=1;value[0]='T';
    for(size_t j=0;j<p->length;j++) {
      if(p->data[j]==0x0a){value[used++]=0xff;value[used++]=1;}
      else if(p->data[j]==0xff){value[used++]=0xff;value[used++]=0;}
      else value[used++]=p->data[j];
    }
    add_record(rus,(unsigned char *)key,(size_t)n,value,used);free(value);
  }
}

static size_t alphabet_index(unsigned char c,int buckets) {
  c=fold(c); if(buckets==26){if(c>='a'&&c<='z')return c-'a';return (size_t)-1;}
  if(c>=0xa0&&c<=0xaf)return c-0xa0;if(c>=0xe0&&c<=0xef)return c-0xe0+16;return (size_t)-1;
}
static void write_dictionary(const char *path,Records *db,const char *language,int buckets) {
  qsort(db->items,db->count,sizeof(Record),record_compare);
  size_t index_count=(size_t)buckets*(buckets+1),index_size=index_count*4,body_len=2;
  for(size_t i=0;i<db->count;i++)body_len+=db->items[i].key_len+1+db->items[i].value_len+1;
  if(body_len>UINT32_MAX-HEADER_SIZE-index_size)fail("dictionary exceeds 32-bit LTech image limits");
  size_t total=HEADER_SIZE+body_len+index_size;unsigned char *image=calloc(total,1);if(!image)fail("out of memory");
  memcpy(image,"LTech DIC File 2.00 ",20);image[20]=0x1a;memcpy(image+21,language,3);image[24]=0;image[25]=2;image[26]=2;put16(image+28,(uint16_t)buckets);
  size_t p=HEADER_SIZE;image[p++]='\n';size_t cols=(size_t)buckets+1;uint32_t *slots=allocate(index_count*sizeof(uint32_t));for(size_t i=0;i<index_count;i++)slots[i]=EMPTY_SLOT;uint32_t first[32];for(int i=0;i<32;i++)first[i]=EMPTY_SLOT;
  for(size_t i=0;i<db->count;i++) {
    Record *r=&db->items[i];size_t offset=p-HEADER_SIZE-1; /* byte before the indexed key */
    size_t row=alphabet_index(r->key[0],buckets);
    if(row!=(size_t)-1){size_t col=r->key_len>1?alphabet_index(r->key[1],buckets):(size_t)-1;if(col==(size_t)-1)col=(size_t)buckets;size_t at=row*cols+col;if(slots[at]==EMPTY_SLOT)slots[at]=(uint32_t)(HEADER_SIZE+offset);if(first[row]==EMPTY_SLOT)first[row]=(uint32_t)(HEADER_SIZE+offset);}
    memcpy(image+p,r->key,r->key_len);p+=r->key_len;image[p++]='*';memcpy(image+p,r->value,r->value_len);p+=r->value_len;image[p++]='\n';
  }
  image[p++]='\n';
  for(int row=0;row<buckets;row++){if(slots[row*cols+row]==EMPTY_SLOT&&first[row]!=EMPTY_SLOT)slots[row*cols+row]=first[row];if(slots[row*cols+buckets]==EMPTY_SLOT&&first[row]!=EMPTY_SLOT)slots[row*cols+buckets]=first[row];}
  put32(image+30,(uint32_t)p);put32(image+34,(uint32_t)total);
  for(size_t i=0;i<index_count;i++)put32(image+p+i*4,slots[i]);
  FILE *out=fopen(path,"wb");if(!out){perror(path);exit(1);}if(fwrite(image,1,total,out)!=total)fail("failed writing dictionary image");fclose(out);free(slots);free(image);
}

static void command_build(int argc,char **argv) {
  if(argc!=6)fail("usage: openrussian_db build SOURCE_DIR OUTPUT.DIC OUTPUT.RUS OUTPUT.MORPH");
  const char *dir=argv[2];size_t need=strlen(dir)+32;char *path=allocate(need);Records source_dic={0},source_rus={0},morph={0};
  /* The demo's closed-class and common-verb readings must outrank unrelated
   * homonyms that become visible when importing the complete tables. */
  add_utf8_record(&source_dic,"a","T");add_utf8_record(&source_dic,"an","T");add_utf8_record(&source_dic,"the","T");
  add_utf8_record(&source_dic,"i","R011я");
  add_utf8_record(&source_dic,"want","e00хотеть");add_utf8_record(&source_dic,"wants","e00хотеть");
  add_utf8_record(&source_dic,"can","e00мочь");
  snprintf(path,need,"%s/others.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"other");
  snprintf(path,need,"%s/nouns.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"noun");
  snprintf(path,need,"%s/verbs.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"verb");
  snprintf(path,need,"%s/adjectives.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"adjective");
  add_people_plural(&source_rus);emit_morphology_patterns(&morph);
  write_dictionary(argv[3],&source_dic,"ERS",26);write_dictionary(argv[4],&source_rus,"RS",32);write_dictionary(argv[5],&morph,"RS",32);
  printf("wrote %zu OpenRussian DIC records, %zu RUS records, and %zu morphology records; replaced %zu unsupported codepoints\n",source_dic.count,source_rus.count,morph.count,unrepresentable_codepoints);free(path);
}
static void command_info(const char *path) {
  FILE *f=fopen(path,"rb");if(!f){perror(path);exit(1);}unsigned char h[HEADER_SIZE];if(fread(h,1,sizeof h,f)!=sizeof h||memcmp(h,"LTech DIC File 2.00 ",20))fail("not an LTech DIC image");
  if(fseek(f,0,SEEK_END))fail("seek failed");long length=ftell(f);uint32_t end=get32(h+30),size=get32(h+34);uint16_t buckets=h[28]|(uint16_t)h[29]<<8;uint32_t idx=(uint32_t)buckets*(buckets+1)*4;size_t count=0;
  if(end>=HEADER_SIZE&&end<=size&&size==(uint32_t)length&&end+idx==size){rewind(f);fseek(f,HEADER_SIZE,SEEK_SET);int c;size_t line_len=0;while((long)ftell(f)<(long)end&&(c=fgetc(f))!=EOF){if(c=='\n'){if(line_len)count++;line_len=0;}else line_len++;}}
  printf("file=%s\nlanguage=%.*s\nalphabet=%u\nbytes=%ld\nentries=%zu\nindex=%s\n",path,3,h+21,buckets,length,count,(end+idx==(uint32_t)length&&size==(uint32_t)length)?"present":"invalid");fclose(f);
}
static void command_find(const char *path,const char *wanted) {
  FILE *f=fopen(path,"rb");if(!f){perror(path);exit(1);}unsigned char h[HEADER_SIZE];if(fread(h,1,sizeof h,f)!=sizeof h||memcmp(h,"LTech DIC File 2.00 ",20))fail("not an LTech DIC image");uint32_t end=get32(h+30);size_t keylen;unsigned char *key=to_cp866(wanted,&keylen);char *line=NULL;size_t cap=0;size_t found=0;
  if(fseek(f,HEADER_SIZE,SEEK_SET))fail("seek failed");int c;
  while((long)ftell(f)<(long)end&&(c=fgetc(f))!=EOF){
    if(c=='\n')continue;size_t n=0;
    while(c!=EOF&&c!='\n'){if(n+2>cap){cap=cap?cap*2:128;line=realloc(line,cap);if(!line)fail("out of memory");}line[n++]=(char)c;c=fgetc(f);}
    line[n]=0;char *star=memchr(line,'*',n);
    if(star&&(size_t)(star-line)==keylen){
      int same=1;for(size_t i=0;i<keylen;i++)if(fold((unsigned char)line[i])!=fold(key[i]))same=0;
      if(same){
        char *kutf=from_cp866((unsigned char *)line,keylen);printf("%s*",kutf);free(kutf);
        const unsigned char *value=(unsigned char *)star+1;size_t value_len=n-keylen-1;
        int ltech_code=h[21]=='R'&&h[22]=='S'&&value_len&&(value[0]=='N'||value[0]=='A'||value[0]=='V');
        if(ltech_code||memchr(value,0,value_len)){for(size_t i=0;i<value_len;i++)printf("%02X",value[i]);putchar('\n');}
        else{char *vutf=from_cp866(value,value_len);printf("%s\n",vutf);free(vutf);}
        found++;
      }
    }
  }
  if(!found)printf("no entries\n");free(key);free(line);fclose(f);
}
int main(int argc,char **argv) {
  if(argc<2)fail("usage: openrussian_db build|info|find ...");
  if(!strcmp(argv[1],"build"))command_build(argc,argv);
  else if(!strcmp(argv[1],"info")&&argc==3)command_info(argv[2]);
  else if(!strcmp(argv[1],"find")&&argc==4)command_find(argv[2],argv[3]);
  else fail("usage: openrussian_db build SOURCE_DIR OUTPUT.DIC OUTPUT.RUS OUTPUT.MORPH | info FILE | find FILE HEADWORD");
  return 0;
}
