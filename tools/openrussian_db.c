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

typedef struct { unsigned char *key, *value; size_t key_len, value_len, sequence; int primary, gloss; long rank; } Record;
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
  r->value=allocate(value_len);memcpy(r->value,value,value_len);r->value_len=value_len;r->sequence=next_sequence++;r->primary=0;r->gloss=99;r->rank=0;
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

/* Native `e` marks an English verb whose base form is also its past or
 * participle (come, read, put); LTGOLD codes only these words so. Coding every
 * verb `e` made a clause-initial imperative a participle (Give me -> Данное). */
static int coincident_form(const char *alias) {
  static const char *words[]={"assured","become","come","cost","cut","fed","hit","let","misread","put","read","set","spit"};
  for(size_t i=0;i<sizeof words/sizeof *words;i++)if(!strcmp(alias,words[i]))return 1;
  return 0;
}
static int is_verb_record(const Record *r) { return r->value_len>3&&(r->value[0]=='e'||r->value[0]=='V'); }
static int is_plain_adverb(const char *alias,const char *lemma);
static char verb_frame(const char *alias);
static void add_english_alias(Records *dic,const char *alias,const char *pos,const char *lemma,const char *aspect,int plural) {
  /* OpenRussian's `others` table has uninflected words and fixed expressions
   * without a part of speech. Native LTGOLD codes most such words as D
   * (`at all*Dсовсем`, `today*Dсегодня`). Keep them in a W composite so
   * reordering leaves these unclassified words in place. Do not use the `#`
   * class: it is for nontranslated names and reads a leading с/м/ж as gender. */
  if(!strcmp(pos,"other")) {
    size_t alias_len,lemma_len;unsigned char *key=to_cp866(alias,&alias_len),*lemma_bytes=to_cp866(lemma,&lemma_len);
    /* A one-word adverb is a plain D, as in LTGOLD: native rules such as
     * `X D V` (will always supply) do not see through a W composite. */
    int plain=is_plain_adverb(alias,lemma);
    unsigned char *value=allocate(lemma_len+2);size_t at=0;if(!plain)value[at++]='W';value[at++]='D';memcpy(value+at,lemma_bytes,lemma_len);
    add_record(dic,key,alias_len,value,lemma_len+at);free(key);free(lemma_bytes);free(value);return;
  }
  const char *russian_lemma=plural&&!strcmp(pos,"noun")&&!strcmp(alias,"people")&&!strcmp(lemma,"человек")?"люди":lemma;
  size_t lemma_len; unsigned char *encoded=to_cp866(russian_lemma,&lemma_len);
  unsigned char *value=allocate(lemma_len+8); size_t used=0;
  if(!strcmp(pos,"noun")){value[used++]=plural?'n':'N';}
  else if(!strcmp(pos,"verb")){value[used++]=coincident_form(alias)?'e':'V';value[used++]=verb_frame(alias);value[used++]=!strcmp(aspect,"perfective")?'1':'0';}
  else value[used++]='A';
  memcpy(value+used,encoded,lemma_len);used+=lemma_len;
  size_t alias_len; unsigned char *key=to_cp866(alias,&alias_len);add_record(dic,key,alias_len,value,used);
  free(encoded);free(value);free(key);
}
static void parse_glosses(Records *dic,const char *gloss,const char *pos,const char *lemma,const char *aspect,long rank) {
  char *copy=strdup(gloss); if(!copy)fail("out of memory");
  char *group_save=NULL;int first=1,index=0,depth=0;
  for(char *group=strtok_r(copy,";",&group_save);group;group=strtok_r(NULL,";",&group_save)) {
    char *alias_save=NULL;
    for(char *alias=strtok_r(group,",",&alias_save);alias;alias=strtok_r(NULL,",",&alias_save)) {
      while(*alias==' '||*alias=='\t')alias++; size_t n=strlen(alias);while(n&&(alias[n-1]==' '||alias[n-1]=='\t'))alias[--n]=0;
      while(n&&strchr(".!?;:",alias[n-1]))alias[--n]=0;
      if(!n)continue; lower_ascii(alias);
      /* Some verb glosses carry the infinitive marker (to go); as keys they
       * shadowed every infinitive (I want to go -> пройнный). */
      if(!strcmp(pos,"verb")&&!strncmp(alias,"to ",3)){alias+=3;while(*alias==' ')alias++;if(!*alias)continue;}
      /* A multiword gloss is a description, not a headword: as a literal key
       * it would win over grammar and phrase rules. Phrases live in dictionary.txt. */
      /* "growth (in quantity, prices, etc)" splits at its commas; everything
       * from an open parenthesis to its close is a note, not a gloss. */
      {int was=depth;for(char *c=alias;*c;c++){if(*c=='(')depth++;else if(*c==')'&&depth>0)depth--;}
       if(was||depth){index++;first=0;continue;}}
      if(strchr(alias,' ')){index++;first=0;continue;}
      int plural=!strcmp(pos,"noun")&&(!strcmp(alias,"people")||!strcmp(alias,"children"));
      add_english_alias(dic,alias,pos,lemma,aspect,plural);
      /* The first gloss is the row's primary sense (visit: посещать). */
      dic->items[dic->count-1].rank=rank;dic->items[dic->count-1].gloss=index++;
      if(first&&strcmp(pos,"other")){dic->items[dic->count-1].primary=1;}
      first=0;
      if(!strcmp(pos,"noun")&&!strcmp(lemma,"ребёнок")&&!strcmp(alias,"child"))
        add_english_alias(dic,"children",pos,lemma,aspect,1);
    }
  }
  free(copy);
}

/* openrussian/lexemes.tsv and openrussian/words.tsv: attributes the OpenRussian
 * tables lack, one `key<TAB>attribute[<TAB>value]` row each. LTGOLD keeps the
 * same facts as bytes inside its .RUS/.DIC records. */
static char **na_nouns;static size_t na_noun_count;
static char **imperfective_only;static size_t imperfective_only_count;
static char **content_first;static size_t content_first_count;
static char **plain_adverbs;static size_t plain_adverb_count;
static char **partner_pairs;static size_t partner_pair_count;
static char **government_lemma;static unsigned char *government_byte;static size_t government_count;
static char **frame_verb;static char *frame_digit_of;static size_t frame_count;
static void push(char ***list,size_t *count,const char *item) {
  *list=realloc(*list,(*count+1)*sizeof **list);if(!*list||!((*list)[(*count)++]=strdup(item)))fail("out of memory");
}
static void load_attributes(const char *path,int russian) {
  FILE *file=fopen(path,"r");if(!file){perror(path);exit(1);}char *line=NULL;size_t cap=0;
  while(getline(&line,&cap,file)>=0) {
    size_t n=strcspn(line,"\r\n");line[n]=0;if(!n||line[0]=='#')continue;
    char *tab=strchr(line,'\t');if(!tab)fail("attribute row needs key<TAB>attribute");*tab=0;
    const char *key=line,*attribute=tab+1,*value="";char *tab2=strchr(tab+1,'\t');if(tab2){*tab2=0;value=tab2+1;}
    if(russian&&!strcmp(attribute,"na"))push(&na_nouns,&na_noun_count,key);
    else if(russian&&!strcmp(attribute,"imperfective-only"))push(&imperfective_only,&imperfective_only_count,key);
    else if(russian&&!strcmp(attribute,"partner")){if(!*value)fail("partner needs a verb");push(&partner_pairs,&partner_pair_count,key);push(&partner_pairs,&partner_pair_count,value);}
    else if(russian&&!strcmp(attribute,"government")){
      if(!*value)fail("government needs a hex byte");push(&government_lemma,&government_count,key);
      government_byte=realloc(government_byte,government_count*sizeof *government_byte);if(!government_byte)fail("out of memory");
      government_byte[government_count-1]=(unsigned char)strtoul(value,NULL,16);}
    else if(!russian&&!strcmp(attribute,"adverb"))push(&plain_adverbs,&plain_adverb_count,key);
    else if(!russian&&!strcmp(attribute,"content-first"))push(&content_first,&content_first_count,key);
    else if(!russian&&!strcmp(attribute,"frame")){
      if(!*value)fail("frame needs a digit");push(&frame_verb,&frame_count,key);
      frame_digit_of=realloc(frame_digit_of,frame_count);if(!frame_digit_of)fail("out of memory");frame_digit_of[frame_count-1]=value[0];}
    else{fprintf(stderr,"%s: unknown attribute %s for %s\n",path,attribute,key);exit(1);}
  }
  free(line);fclose(file);
}
static int is_na_noun(const char *lemma) { for(size_t i=0;i<na_noun_count;i++)if(!strcmp(na_nouns[i],lemma))return 1; return 0; }
/* A one-word adverb is plain D: every -ly word plus the listed ones. Other
 * unclassified words may be prepositions or conjunctions and keep W. */
static int is_plain_adverb(const char *alias,const char *lemma) {
  if(strchr(alias,' ')||strchr(lemma,' '))return 0;
  size_t n=strlen(alias);if(n>4&&!strcmp(alias+n-2,"ly"))return 1;
  for(size_t i=0;i<plain_adverb_count;i++)if(!strcmp(plain_adverbs[i],alias))return 1;
  return 0;
}
static int is_content_first(const char *word) { for(size_t i=0;i<content_first_count;i++)if(!strcmp(content_first[i],word))return 1; return 0; }
static const char *curated_partner(const char *lemma) { for(size_t i=0;i+1<partner_pair_count;i+=2)if(!strcmp(partner_pairs[i],lemma))return partner_pairs[i+1]; return NULL; }
static int is_imperfective_only(const char *lemma) { for(size_t i=0;i<imperfective_only_count;i++)if(!strcmp(imperfective_only[i],lemma))return 1; return 0; }

#define LEXEME_SLOTS (1u<<18)
static unsigned char **lexeme_slots;static size_t *lexeme_lengths;
/* Returns 1 the first time (key, class) is seen, 0 afterwards. */
static int lexeme_seen(const unsigned char *key,size_t n,unsigned char cls) {
  if(!lexeme_slots){lexeme_slots=calloc(LEXEME_SLOTS,sizeof *lexeme_slots);lexeme_lengths=calloc(LEXEME_SLOTS,sizeof *lexeme_lengths);if(!lexeme_slots||!lexeme_lengths)fail("out of memory");}
  uint64_t h=1469598103934665603ULL^cls;for(size_t i=0;i<n;i++)h=(h^key[i])*1099511628211ULL;
  for(size_t at=h&(LEXEME_SLOTS-1);;at=(at+1)&(LEXEME_SLOTS-1)) {
    unsigned char *slot=lexeme_slots[at];
    if(!slot){slot=allocate(n+1);slot[0]=cls;memcpy(slot+1,key,n);lexeme_slots[at]=slot;lexeme_lengths[at]=n;return 1;}
    if(lexeme_lengths[at]==n&&slot[0]==cls&&!memcmp(slot+1,key,n))return 0;
  }
}

/* Native verb records name the perfective partner after the code
 * (LTGOLD видеть*V\xc1\x88\xbc\x80увидеть); senses.lua follows it when the
 * grammar requests perfective aspect, e.g. for the future after will. */
typedef struct { char *lemma, *aspect, *partner; } Verb;
static Verb *verbs;static size_t verb_count;
static int verb_compare(const void *a,const void *b) { return strcmp(((const Verb *)a)->lemma,((const Verb *)b)->lemma); }
static void load_verbs(const char *path) {
  FILE *file=fopen(path,"r");if(!file){perror(path);exit(1);}char *line=NULL;size_t cap=0;
  if(getline(&line,&cap,file)<0)fail("empty source TSV");
  Fields header=parse_tsv(line);size_t bare=column(&header,"bare"),aspect=column(&header,"aspect"),partner=column(&header,"partner");
  if(bare==(size_t)-1||aspect==(size_t)-1||partner==(size_t)-1)fail("verbs.tsv is missing aspect/partner columns");
  char *row_line=NULL;size_t row_cap=0;
  while(getline(&row_line,&row_cap,file)>=0) {
    if(row_line[0]=='#'||row_line[0]=='\n')continue;Fields row=parse_tsv(row_line);
    if(is_empty(cell(&row,bare)))continue;
    verbs=realloc(verbs,(verb_count+1)*sizeof *verbs);if(!verbs)fail("out of memory");
    Verb *v=&verbs[verb_count++];v->lemma=strdup(cell(&row,bare));v->aspect=strdup(cell(&row,aspect));v->partner=strdup(cell(&row,partner));
    if(!v->lemma||!v->aspect||!v->partner)fail("out of memory");
    /* The column mixes ; and , separators and keeps stress marks (поплы'ть). */
    char *out=v->partner;for(char *p=v->partner;*p;p++){if(*p=='\''||*p==' ')continue;*out++=*p==','?';':*p;}*out=0;
  }
  /* Stable for duplicate lemmas: the first source row stays first. */
  for(size_t i=1;i<verb_count;i++){Verb v=verbs[i];size_t j=i;while(j&&strcmp(verbs[j-1].lemma,v.lemma)>0){verbs[j]=verbs[j-1];j--;}verbs[j]=v;}
  free(line);free(row_line);fclose(file);
}
static int lists(const char *list,const char *word) {
  size_t n=strlen(word);
  for(const char *p=list;*p;){const char *end=strchr(p,';');size_t len=end?(size_t)(end-p):strlen(p);
    if(len==n&&!strncmp(p,word,n))return 1;if(!end)break;p=end+1;}
  return 0;
}
static const Verb *find_perfective(const char *lemma) {
  Verb key={(char *)lemma,NULL,NULL};const Verb *v=bsearch(&key,verbs,verb_count,sizeof *verbs,verb_compare);
  if(!v)return NULL;while(v>verbs&&!strcmp(v[-1].lemma,lemma))v--;
  for(;v<verbs+verb_count&&!strcmp(v->lemma,lemma);v++)if(!strcmp(v->aspect,"perfective"))return v;
  return NULL;
}
static const char *verb_aspect(const char *lemma) {
  Verb key={(char *)lemma,NULL,NULL};const Verb *v=bsearch(&key,verbs,verb_count,sizeof *verbs,verb_compare);
  if(!v)return "";while(v>verbs&&!strcmp(v[-1].lemma,lemma))v--;
  return v->aspect;
}
/* The first perfective partner that names this verb back, else the first
 * perfective partner: видеть -> увидеть (not завидеть), говорить -> сказать. */
static const char *perfective_partner(const char *lemma) {
  Verb key={(char *)lemma,NULL,NULL};const Verb *v=bsearch(&key,verbs,verb_count,sizeof *verbs,verb_compare);
  if(!v)return NULL;while(v>verbs&&!strcmp(v[-1].lemma,lemma))v--;
  if(strcmp(v->aspect,"imperfective")||is_imperfective_only(lemma))return NULL;
  const char *curated=curated_partner(lemma);if(curated)return curated;
  const char *fallback=NULL;char *copy=strdup(v->partner),*save=NULL;if(!copy)fail("out of memory");
  static char chosen[256];const char *result=NULL;
  for(char *p=strtok_r(copy,";",&save);p;p=strtok_r(NULL,";",&save)) {
    while(*p==' ')p++;const Verb *pf=find_perfective(p);if(!pf)continue;
    if(lists(pf->partner,lemma)){result=pf->lemma;break;}
    if(!fallback)fallback=pf->lemma;
  }
  if(!result)result=fallback;
  if(result){snprintf(chosen,sizeof chosen,"%s",result);result=chosen;}
  free(copy);return result;
}

/* The runtime lowers a capitalized DIC lemma (Россия) and looks its metadata
 * up under the lowercase headword, as LTGOLD stores them (россия). Keep the
 * capitalized spelling in the DIC reading only. */
/* 5,122 OpenRussian nouns leave the gender column empty, which became neuter
 * (main factor -> Главное фактор). Read the gender off the lemma ending. */
static int has_suffix(const char *word,const char *tail) { size_t n=strlen(word),m=strlen(tail);return n>=m&&!strcmp(word+n-m,tail); }
static const char *inferred_gender(const char *lemma) {
  static const char *feminine[]={"а","я","сть","знь","вь","бь","пь","мь","чь"};
  static const char *neuter[]={"о","е","ё","мя"};
  for(size_t i=0;i<sizeof neuter/sizeof *neuter;i++)if(has_suffix(lemma,neuter[i]))return "n";
  for(size_t i=0;i<sizeof feminine/sizeof *feminine;i++)if(has_suffix(lemma,feminine[i]))return "f";
  return "m";
}
/* Verb government byte (0x80 intransitive, 0x84 dative, 0x90 instrumental);
 * every verb without a lexemes.tsv row stays transitive 0x88. */
static unsigned char verb_government(const char *lemma) {
  for(size_t i=0;i<government_count;i++)if(!strcmp(government_lemma[i],lemma))return government_byte[i];
  return 0x88;
}
static char verb_frame(const char *alias) {
  for(size_t i=0;i<frame_count;i++)if(!strcmp(frame_verb[i],alias))return frame_digit_of[i];
  return '0';
}
/* Paradigm assignments from tools/fit_paradigms.lua: pos<TAB>lemma<TAB>aspect
 * <TAB>id<TAB>matched<TAB>forms. A fitted lexeme gets LTGOLD's paradigm byte
 * (0x80|id) in its .RUS record and no stored forms in BASE.MORPH. */
typedef struct { char *key; unsigned char id; } Fit;
static Fit *fits;static size_t fit_count;
static char *fold_yo(const char *s) {
  char *out=strdup(s);if(!out)fail("out of memory");
  for(char *c=out;*c;c++) {
    if((unsigned char)c[0]==0xD1&&(unsigned char)c[1]==0x91){c[0]=(char)0xD0;c[1]=(char)0xB5;c++;}
    else if((unsigned char)c[0]==0xD0&&(unsigned char)c[1]==0x81){c[0]=(char)0xD0;c[1]=(char)0x95;c++;}
  }
  return out;
}
static char *fit_key(const char *pos,const char *lemma,const char *aspect) {
  char *folded=fold_yo(lemma);size_t n=strlen(folded)+8;char *key=allocate(n);
  snprintf(key,n,"%c%s%s",pos[0],folded,!strcmp(pos,"verb")&&!strcmp(aspect,"perfective")?"/1":"/0");free(folded);return key;
}
static int fit_compare(const void *a,const void *b) { return strcmp(((const Fit *)a)->key,((const Fit *)b)->key); }
static void load_fits(const char *path) {
  FILE *file=fopen(path,"r");if(!file){perror(path);exit(1);}char *line=NULL;size_t cap=0;size_t capacity=0;
  while(getline(&line,&cap,file)>=0) {
    size_t n=strcspn(line,"\r\n");line[n]=0;if(!n||line[0]=='#')continue;
    char *f[6];size_t k=0;char *save=NULL;for(char *tok=strtok_r(line,"\t",&save);tok&&k<6;tok=strtok_r(NULL,"\t",&save))f[k++]=tok;
    if(k<4)fail("fit row needs pos<TAB>lemma<TAB>aspect<TAB>id");
    if(fit_count==capacity){capacity=capacity?capacity*2:1024;fits=realloc(fits,capacity*sizeof *fits);if(!fits)fail("out of memory");}
    const char *pos=f[0][0]=='v'?"verb":f[0][0]=='n'?"noun":"adjective";
    fits[fit_count].key=fit_key(pos,f[1],f[2][0]=='1'?"perfective":"imperfective");fits[fit_count].id=(unsigned char)strtoul(f[3],NULL,10);fit_count++;
  }
  free(line);fclose(file);qsort(fits,fit_count,sizeof *fits,fit_compare);
}
static int fitted_paradigm(const char *pos,const char *lemma,const char *aspect) {
  if(!fit_count)return -1;char *key=fit_key(pos,lemma,aspect?aspect:"");Fit probe={key,0};
  Fit *found=bsearch(&probe,fits,fit_count,sizeof *fits,fit_compare);free(key);return found?found->id:-1;
}
static void lower_initial(unsigned char *key) { key[0]=fold(key[0]); }
static void add_russian_lexeme(Records *rus,const char *pos,const char *lemma,const char *gender,const char *animate,const char *sg_only,const char *pl_only,const char *aspect_cell) {
  size_t n; unsigned char *encoded=to_cp866(lemma,&n), value[5+256]; size_t used=0;
  int paradigm=fitted_paradigm(pos,lemma,aspect_cell);unsigned char paradigm_byte=paradigm>=0?(unsigned char)(0x80|paradigm):0;
  if(!strcmp(pos,"noun")) {
    /* Native noun flags: 0x80 base, 0x02 animate (from/от, animate
     * accusative), 0x40 на-location noun. */
    value[used++]='N';value[used++]=(unsigned char)(0x80|(!strcmp(animate,"1")?0x02:0)|(is_na_noun(lemma)?0x40:0));
    /* Keep the legacy RUS number bits beside the 2-bit gender code. */
    if(is_empty(gender))gender=inferred_gender(lemma);
    int g=!strcmp(gender,"m")?1:!strcmp(gender,"f")?2:0;
    value[used++]=(unsigned char)(0x80|g|(!strcmp(pl_only,"1")?0x08:0)|(!strcmp(sg_only,"1")?0x04:0));
    value[used++]=paradigm_byte;
  } else if(!strcmp(pos,"verb")) {
    /* Byte-2 aspect flags. 0x08 (verified in original LTPRO): future is
     * analytic буду работать, ignoring any partner. 0x04 forces perfective
     * aspect in the decoder; native perfectives mostly carry 0x02 instead
     * (увидеть e3), which also suppresses the partner lookup. */
    const char *partner=perfective_partner(lemma),*aspect=verb_aspect(lemma);
    value[used++]='V';value[used++]=(unsigned char)(0xc0|(!strcmp(aspect,"perfective")?0x04:partner?0:0x08));
    value[used++]=verb_government(lemma);value[used++]=paradigm_byte;value[used++]=0;
    if(partner){size_t m;unsigned char *p=to_cp866(partner,&m);if(m>255)fail("verb partner too long");memcpy(value+used,p,m);used+=m;free(p);}
  }
  else { value[used++]='A';value[used++]=0xc0;value[used++]=paradigm_byte;value[used++]=0; }
  /* LTGOLD keys adjectives by the stem without the two-letter ending (красн,
   * больш): the native lookup cuts the ending before searching .RUS. */
  if(!strcmp(pos,"adjective")&&n>2)n-=2;
  /* One lexeme per (headword, class); a hash set replaces a linear scan. */
  lower_initial(encoded);
  if(!lexeme_seen(encoded,n,value[0])){free(encoded);return;}
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
  /* A fitted lexeme declines from its paradigm. Nouns and verbs then need no
   * stored forms; adjectives keep the comparative, superlative and short forms,
   * which the native tables do not have. */
  int fitted=fitted_paradigm(pos,lemma,aspect)>=0;
  if(fitted&&strcmp(pos,"adjective"))return;
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
    const char *source=fitted&&!strncmp(slots[i],"decl_",5)?"":cell(row,column(header,slots[i]));char *copy=strdup(source);if(!copy)fail("out of memory");
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
  lower_initial(encoded_lemma);add_record(morph,encoded_lemma,lemma_len,value,7);free(encoded_lemma);free(pattern);
}

static void import_file(Records *source_dic,Records *source_rus,Records *morph,const char *path,const char *pos) {
  FILE *file=fopen(path,"r");if(!file){perror(path);exit(1);}char *line=NULL;size_t cap=0;ssize_t n=getline(&line,&cap,file);if(n<0)fail("empty source TSV");
  Fields header=parse_tsv(line);size_t bare=column(&header,"bare"), gloss=column(&header,"translations_en"), gender=column(&header,"gender"), aspect=column(&header,"aspect"), sg_only=column(&header,"sg_only"), animate=column(&header,"animate"), pl_only=column(&header,"pl_only"), source_row=column(&header,"source_row");
  if(bare==(size_t)-1||gloss==(size_t)-1||source_row==(size_t)-1)fail("source TSV is missing required columns");
  while((n=getline(&line,&cap,file))>=0) {
    if(line[0]=='#'||line[0]=='\n')continue;Fields row=parse_tsv(line);const char *lemma=cell(&row,bare),*english=cell(&row,gloss),*g=cell(&row,gender),*a=cell(&row,aspect);
    if(is_empty(lemma))continue;
    if(is_empty(cell(&row,source_row)))fail("OpenRussian row is missing source_row id");
    if(strcmp(pos,"other"))add_russian_lexeme(source_rus,pos,lemma,g,cell(&row,animate),cell(&row,sg_only),cell(&row,pl_only),a);
    if(!is_empty(english))parse_glosses(source_dic,english,pos,lemma,a,strtol(cell(&row,source_row),NULL,10));
    add_forms(morph,&header,&row,pos,lemma,a);
  }
  free(line);fclose(file);
}

/* OpenRussian lists some plural nouns as their own glosses (works ->
 * производство). Such a literal shadows suffix analysis of the verb's -s form,
 * so "He works" printed "Он производство". Native LTGOLD codes these
 * homographs as one ambiguous v/n record, `accesses*zуправлятьnдоступ\access`,
 * and lets grammar choose. Put the same record first for every one-word noun
 * gloss ending in -s whose stem is a verb gloss, that is not a verb gloss, and
 * whose noun the stem lacks. */
static int key_compare(const Record *a,const unsigned char *key,size_t len) {
  size_t n=a->key_len<len?a->key_len:len;
  for(size_t i=0;i<n;i++){unsigned char x=fold(a->key[i]),y=fold(key[i]);if(x!=y)return x<y?-1:1;}
  return a->key_len==len?0:(a->key_len<len?-1:1);
}
static size_t group_start(Records *db,const unsigned char *key,size_t len) {
  size_t lo=0,hi=db->count;
  while(lo<hi){size_t mid=(lo+hi)/2;if(key_compare(&db->items[mid],key,len)<0)lo=mid+1;else hi=mid;}
  return lo;
}
static int has_verb(Records *db,const unsigned char *key,size_t len) {
  for(size_t i=group_start(db,key,len);i<db->count&&!key_compare(&db->items[i],key,len);i++)
    if(is_verb_record(&db->items[i]))return 1;
  return 0;
}
/* Prefer an imperfective reading: a perfective lemma's present form is future
 * (He leaves -> выйдет). */
/* Choose a reading of one class for a key. The source tables are sorted by
 * frequency (source_row); a row listing the key as its first gloss is that
 * row's primary sense. Take the primary reading unless it is much rarer than
 * the most frequent one (10x for verbs, 2x otherwise): call -> звать (not
 * называть), visit -> посещать, but stay -> оставаться (not гостить),
 * photograph -> фотография (not фотокарточка).
 * Verbs prefer the imperfective. */
static const Record *choose_reading(Records *db,const unsigned char *key,size_t len,const char *classes,int verbs) {
  const Record *frequent=NULL,*primary=NULL,*any=NULL;int imperfective=0;
  if(verbs)for(size_t i=group_start(db,key,len);i<db->count&&!key_compare(&db->items[i],key,len);i++)
    if(is_verb_record(&db->items[i])&&db->items[i].value[2]=='0')imperfective=1;
  for(size_t i=group_start(db,key,len);i<db->count&&!key_compare(&db->items[i],key,len);i++) {
    const Record *r=&db->items[i];
    if(verbs?!is_verb_record(r):(r->value_len<2||!strchr(classes,r->value[0])))continue;
    if(verbs&&imperfective&&r->value[2]!='0')continue;
    if(!any)any=r;
    /* Frequency counts only where the key is among the row's first glosses
     * (бывать is frequent as "be", and lists "visit" third). */
    if(!frequent&&r->gloss<=(verbs?1:4))frequent=r;
    if(r->primary&&!primary)primary=r;
  }
  if(primary&&frequent&&frequent->rank>0&&primary->rank>(verbs?10:2)*frequent->rank)return frequent;
  return primary?primary:frequent?frequent:any;
}
static int has_primary(Records *db,const unsigned char *key,size_t len,const char *classes) {
  for(size_t i=group_start(db,key,len);i<db->count&&!key_compare(&db->items[i],key,len);i++)
    if(db->items[i].primary&&db->items[i].value_len>1&&strchr(classes,db->items[i].value[0]))return 1;
  return 0;
}
static const Record *stem_verb(Records *db,const unsigned char *key,size_t len) { return choose_reading(db,key,len,NULL,1); }
/* Whether the stem already has this noun: then suffix analysis of the -s form
 * reaches it and the plural literal adds nothing (conditions -> условие). */
static int stem_has_noun(Records *db,const unsigned char *key,size_t len,const Record *noun) {
  for(size_t i=group_start(db,key,len);i<db->count&&!key_compare(&db->items[i],key,len);i++) {
    const Record *r=&db->items[i];
    if(r->value_len==noun->value_len&&(r->value[0]=='N'||r->value[0]=='n')&&!memcmp(r->value+1,noun->value+1,r->value_len-1))return 1;
  }
  return 0;
}
/* New records go in after the scan: appending while scanning would leave an
 * unsorted tail inside the binary-searched range. */
static void append_pending(Records *db,Records *pending) {
  for(size_t i=0;i<pending->count;i++) {
    Record *r=&pending->items[i];size_t sequence=r->sequence;
    add_record(db,r->key,r->key_len,r->value,r->value_len);db->items[db->count-1].sequence=sequence;
    free(r->key);free(r->value);
  }
  free(pending->items);
}
static void add_s_form_homographs(Records *db) {
  for(size_t i=0;i<db->count;i++)db->items[i].sequence=db->items[i].sequence*2+2;
  qsort(db->items,db->count,sizeof(Record),record_compare);
  size_t original=db->count;Records pending={0};
  for(size_t i=0;i<original;) {
    size_t end=i;while(end<original&&!key_compare(&db->items[end],db->items[i].key,db->items[i].key_len))end++;
    const Record *head=&db->items[i];const unsigned char *k=head->key;size_t n=head->key_len;
    int word=n>2&&k[n-1]=='s';for(size_t j=0;j<n&&word;j++)if(!(k[j]>='a'&&k[j]<='z'))word=0;
    if(word&&(head->value[0]=='N'||head->value[0]=='n')&&!has_verb(db,k,n)) {
      const Record *verb=NULL;size_t stem=0;
      if(has_verb(db,k,n-1)){verb=stem_verb(db,k,n-1);stem=n-1;}
      else if(n>3&&k[n-2]=='e'&&(strchr("sxz",k[n-3])||(k[n-3]=='h'&&(k[n-4]=='c'||k[n-4]=='s')))&&has_verb(db,k,n-2)){verb=stem_verb(db,k,n-2);stem=n-2;}
      if(verb&&verb->value_len>3&&!stem_has_noun(db,k,stem,head)) {
        size_t vlen=verb->value_len-3,nlen=head->value_len-1,len=1+vlen+1+nlen+1+stem;
        unsigned char *value=allocate(len),*key=allocate(n),*q=value;memcpy(key,k,n);
        *q++='z';memcpy(q,verb->value+3,vlen);q+=vlen;*q++='n';memcpy(q,head->value+1,nlen);q+=nlen;*q++='\\';memcpy(q,k,stem);
        add_record(&pending,key,n,value,len);pending.items[pending.count-1].sequence=head->sequence-1;free(key);free(value);
      }
    }
    i=end;
  }
  append_pending(db,&pending);
}

/* One-word keys get one record per OpenRussian reading until merge_readings
 * folds them into the first, so the first decides the classes: unclassified others.tsv adverbs come first (open -> открыто, new ->
 * внове), then nouns (I'll work -> Я есть работой), and a perfective verb can
 * precede its imperfective (He comes -> придет). Following LTGOLD's codings,
 * put one record first:
 * - a verb with another class: the ambiguous Z record, verb reading first
 *   (close*ZV.закрыватьN.закрытиеA.закрытый); grammar chooses;
 * - an others.tsv adverb with an adjective and no verb: the adjective, with
 *   any noun as an alternative (new*AновыйDвновь in LTGOLD);
 * - verbs only, the first perfective: the imperfective (come*eприходить). */
static const Record *first_class(Records *db,const unsigned char *key,size_t len,const char *classes) { return choose_reading(db,key,len,classes,0); }
/* The imperfective named in a perfective verb's partner column. */
static const char *imperfective_partner(const Record *perfective) {
  char *lemma=from_cp866(perfective->value+3,perfective->value_len-3);
  const Verb *v=find_perfective(lemma);free(lemma);
  if(!v)return NULL;
  static char chosen[256];char *copy=strdup(v->partner),*save=NULL;const char *result=NULL;if(!copy)fail("out of memory");
  for(char *p=strtok_r(copy,";",&save);p;p=strtok_r(NULL,";",&save))
    if(!strcmp(verb_aspect(p),"imperfective")){snprintf(chosen,sizeof chosen,"%s",p);result=chosen;break;}
  free(copy);return result;
}
/* The -ing/-ed twin of the -s homographs: a gloss such as reading -> чтение or
 * opened -> открыто hides the verb's own inflected form, so `He is reading`
 * printed a noun and `He opened the door` an adverb. Native LTGOLD codes
 * `calling*GвызыватьNвызов\call` and `opened*EоткрыватьAоткрытый\open`; emit the
 * same ambiguous record, verb form first, for every one-word gloss in -ing or
 * -ed whose stem (plain, +e, -ied -> y, or without a doubled consonant) is a
 * verb. The gloss's noun or adjective reading follows the verb. */
static const Record *inflection_stem(Records *db,const unsigned char *k,size_t n,size_t suffix,unsigned char *stem,size_t *stem_len) {
  size_t base=n-suffix;const Record *verb=NULL;
  if(base>=63)return NULL;
  memcpy(stem,k,base);
  if(suffix==2&&base>=2&&k[base-1]=='i'){stem[base-1]='y';if(has_verb(db,stem,base)){*stem_len=base;return stem_verb(db,stem,base);}memcpy(stem,k,base);}
  if(has_verb(db,stem,base)){*stem_len=base;return stem_verb(db,stem,base);}
  stem[base]='e';if(has_verb(db,stem,base+1)){*stem_len=base+1;return stem_verb(db,stem,base+1);}
  if(base>2&&k[base-1]==k[base-2]&&has_verb(db,stem,base-1)){*stem_len=base-1;return stem_verb(db,stem,base-1);}
  return verb;
}
static void add_inflected_homographs(Records *db,const char *ending,char code,const char *classes) {
  qsort(db->items,db->count,sizeof(Record),record_compare);
  size_t original=db->count,suffix=strlen(ending);Records pending={0};
  for(size_t i=0;i<original;) {
    size_t end=i;while(end<original&&!key_compare(&db->items[end],db->items[i].key,db->items[i].key_len))end++;
    const Record *head=&db->items[i];const unsigned char *k=head->key;size_t n=head->key_len;
    int word=n>suffix+2&&!memcmp(k+n-suffix,ending,suffix);for(size_t j=0;j<n&&word;j++)if(!(k[j]>='a'&&k[j]<='z'))word=0;
    if(word&&!has_verb(db,k,n)) {
      unsigned char stem[64];size_t stem_len=0;
      const Record *verb=inflection_stem(db,k,n,suffix,stem,&stem_len);
      const Record *other=verb?first_class(db,k,n,classes):NULL;
      if(verb&&verb->value_len>3) {
        size_t vlen=verb->value_len-3,olen=other?other->value_len:0,len=2+vlen+olen+1+stem_len;
        unsigned char *value=allocate(len),*q=value;
        *q++=(unsigned char)code;if(verb->value[1]!='0')*q++=verb->value[1];memcpy(q,verb->value+3,vlen);q+=vlen;if(other){memcpy(q,other->value,olen);q+=olen;}*q++='\\';memcpy(q,stem,stem_len);
        add_record(&pending,(unsigned char *)k,n,value,len);pending.items[pending.count-1].sequence=head->sequence-1;free(value);
      }
    }
    i=end;
  }
  append_pending(db,&pending);
}

static void add_verb_noun_homographs(Records *db) {
  qsort(db->items,db->count,sizeof(Record),record_compare);
  size_t original=db->count;Records pending={0};
  for(size_t i=0;i<original;) {
    size_t end=i;while(end<original&&!key_compare(&db->items[end],db->items[i].key,db->items[i].key_len))end++;
    const Record *head=&db->items[i];const unsigned char *k=head->key;size_t n=head->key_len;
    /* A phrasal verb (knock out) takes the same imperfective-first rule. */
    int word=n>1&&head->value[0]!='z';for(size_t j=0;j<n&&word;j++)if(!((k[j]>='a'&&k[j]<='z')||k[j]=='-'||(k[j]==' '&&is_verb_record(head))))word=0;
    if(word) {
      const Record *verb=stem_verb(db,k,n),*noun=first_class(db,k,n,"Nn"),*adj=first_class(db,k,n,"A");
      char *english=from_cp866(k,n);int listed=is_content_first(english);free(english);
      int other=listed&&head->value[0]=='W';
      /* A listed noun-headed adjective (ready*Nчистоган): adjective first. */
      if(listed&&!verb&&adj&&(head->value[0]=='N'||head->value[0]=='n'))other=1;
      unsigned char *value=allocate(2048);size_t len=0;
      /* The builder's curated readings (want*V21хотеть) have no source rank
       * and stay as they are. */
      if(head->rank==0){free(value);i=end;continue;}
      int verb_head=is_verb_record(head),pn=has_primary(db,k,n,"Nn"),pa=has_primary(db,k,n,"A");
      if(verb&&(other||strchr("NnA",head->value[0])||(verb_head&&(pn||pa)))) {
        /* Verb plus the head reading; a listed adverb-headed word takes its
         * noun and adjective readings (close*ZV.закрыватьN.закрытиеA.близкий). */
        const Record *n1=other?noun:head->value[0]=='A'?NULL:noun,*a1=other||head->value[0]=='A'||(pa&&!pn)?adj:NULL;
        /* Keep only readings whose primary sense the key is; an adjective
         * only without such a noun, or noun adjuncts turn adjectival (the
         * house door: домашняя). blind*ZV.ослеплятьA.слепой (LTGOLD Z). */
        if(verb_head){n1=pn?noun:NULL;a1=pa&&!pn?adj:NULL;}
        /* A noun that is only a secondary sense of a primary verb drops out
         * (go: изюминка), as LTGOLD codes go*Vидти. */
        if(n1&&verb->primary&&!other&&!has_primary(db,k,n,"Nn"))n1=NULL;
        if(!n1&&!a1){memcpy(value,verb->value,verb->value_len);len=verb->value_len;}
        else {
        value[len++]='Z';if(verb->value[1]!='0')value[len++]=verb->value[1];value[len++]='V';value[len++]='.';memcpy(value+len,verb->value+3,verb->value_len-3);len+=verb->value_len-3;
        if(n1){value[len++]=n1->value[0];value[len++]='.';memcpy(value+len,n1->value+1,n1->value_len-1);len+=n1->value_len-1;}
        if(a1){value[len++]='A';value[len++]='.';memcpy(value+len,a1->value+1,a1->value_len-1);len+=a1->value_len-1;}
        }
      } else if(!verb&&other&&adj) {
        memcpy(value,adj->value,adj->value_len);len=adj->value_len;
        if(noun){memcpy(value+len,noun->value,noun->value_len);len+=noun->value_len;}
      } else if(verb&&verb!=head&&is_verb_record(head)&&head->value[1]=='0'&&head->value[2]=='1') {
        /* Prefer the perfective's own partner (прийти -> приходить, not the
         * first imperfective, происходить). */
        const char *pair=imperfective_partner(head);
        if(pair){size_t m;unsigned char *p=to_cp866(pair,&m);value[0]=head->value[0];value[1]='0';value[2]='0';memcpy(value+3,p,m);len=3+m;free(p);}
        else{memcpy(value,verb->value,verb->value_len);len=verb->value_len;}
      }
      if(len){add_record(&pending,k,n,value,len);pending.items[pending.count-1].sequence=head->sequence-1;}
      free(value);
    }
    i=end;
  }
  append_pending(db,&pending);
}

/* The native suffix analysis (0A4F:07F2) picks one stem rule per ending. -ed
 * undoes a doubled final consonant (stopped -> stop), so a verb that itself
 * ends in a doubled letter (call, kill, pass) never finds its stem; -ied
 * restores y (tried -> try), so a verb in -ie (lie, die) fails the same way.
 * LTGOLD lists those forms explicitly (`pulled*Eтянуть\pull`,
 * `calling*GвызыватьNвызов\call`); generate the same records. A reading the
 * form already has (called -> имеемый, passing -> перевал) follows the verb. */
static int ends_with(const unsigned char *key,size_t n,const char *tail) {
  size_t m=strlen(tail);return n>=m&&!memcmp(key+n-m,tail,m);
}
static void add_inflected_form(Records *db,Records *pending,size_t original,const unsigned char *stem,size_t n,const char *suffix,char code,const Record *verb,size_t drop) {
  size_t m=n-drop+strlen(suffix);unsigned char *key=allocate(m);memcpy(key,stem,n-drop);memcpy(key+n-drop,suffix,strlen(suffix));
  const Record *existing=NULL;size_t at=group_start(db,key,m);
  if(at<original&&!key_compare(&db->items[at],key,m))existing=&db->items[at];
  unsigned char *value=allocate(verb->value_len+(existing?existing->value_len:0)+n+5);size_t len=0;
  value[len++]=code;if(verb->value[1]!='0')value[len++]=verb->value[1];memcpy(value+len,verb->value+3,verb->value_len-3);len+=verb->value_len-3;
  if(existing&&!memchr(existing->value,'\\',existing->value_len)){memcpy(value+len,existing->value,existing->value_len);len+=existing->value_len;}
  value[len++]='\\';memcpy(value+len,stem,n);len+=n;
  add_record(pending,key,m,value,len);
  pending->items[pending->count-1].sequence=existing?existing->sequence-1:next_sequence++;
  free(value);free(key);
}
static void add_native_suffix_gaps(Records *db) {
  qsort(db->items,db->count,sizeof(Record),record_compare);
  size_t original=db->count;Records pending={0};
  for(size_t i=0;i<original;) {
    size_t end=i;while(end<original&&!key_compare(&db->items[end],db->items[i].key,db->items[i].key_len))end++;
    const unsigned char *k=db->items[i].key;size_t n=db->items[i].key_len;
    int word=1;for(size_t j=0;j<n&&word;j++)if(!(k[j]>='a'&&k[j]<='z'))word=0;
    const Record *verb=word&&n>=3?stem_verb(db,k,n):NULL;
    if(verb) {
      if(n>=4&&k[n-1]==k[n-2]&&strchr("lsfz",k[n-1])) {
        add_inflected_form(db,&pending,original,k,n,"ed",'E',verb,0);
        add_inflected_form(db,&pending,original,k,n,"ing",'G',verb,0);
      } else if(ends_with(k,n,"ie")) {
        add_inflected_form(db,&pending,original,k,n,"d",'E',verb,0);
        add_inflected_form(db,&pending,original,k,n,"ying",'G',verb,2);
      }
    }
    i=end;
  }
  append_pending(db,&pending);
}

/* LTGOLD keeps one record per key: one segment per part of speech, each with
 * its alternative meanings after `;`
 * (table*NN.стол{piece of furniture};инф)таблица{chart}A.табличный,
 * agree*V11V.соглашаться;согласовывать). The runtime prints the alternatives
 * as {1.…}. Fold every other reading of the key into its first record, most
 * frequent first: each segment takes all the key's other lemmas of its class.
 * No segment is added for a class the record lacks: an A. segment on a noun
 * makes grammar read it as an adjective (Is the dog home? -> Псиный дом?).
 * A perfective whose imperfective partner is a reading is the same meaning
 * (grammar chooses the aspect) and is not repeated. */
static int is_lemma_run(unsigned char c) { return !((c>='A'&&c<='Z')||(c>='a'&&c<='z')||c=='\\'); }
static int lemma_ok(const unsigned char *s,size_t n) {
  if(!n)return 0;
  for(size_t i=0;i<n;i++)if(!is_lemma_run(s[i])||strchr(";{}/",s[i]))return 0;
  return 1;
}
/* The lemma a record contributes to a class: V for any verb, else its letter. */
static const unsigned char *reading_lemma(const Record *r,unsigned char cls,size_t *n) {
  size_t skip;
  if(cls=='V'){if(!is_verb_record(r))return NULL;skip=3;}
  else if(cls=='w'){if(r->value_len<3||r->value[0]!='W'||r->value[1]!='D')return NULL;skip=2;}
  else{if(r->value_len<2||r->value[0]!=cls)return NULL;skip=1;}
  *n=r->value_len-skip;
  return lemma_ok(r->value+skip,*n)?r->value+skip:NULL;
}
static int same_text(const unsigned char *a,size_t an,const unsigned char *b,size_t bn) { return an==bn&&!memcmp(a,b,an); }
static int reading_before(const Record *a,const Record *b) {
  if((a->rank>0)!=(b->rank>0))return a->rank>0;
  return a->rank!=b->rank?a->rank<b->rank:a->sequence<b->sequence;
}
/* Whether a perfective's imperfective partner is a verb reading of the group. */
static int partner_listed(Records *db,size_t from,size_t to,const Record *r) {
  if(!is_verb_record(r)||r->value[2]!='1')return 0;
  const char *pair=imperfective_partner(r);if(!pair)return 0;
  size_t m;unsigned char *p=to_cp866(pair,&m);int found=0;
  for(size_t j=from;j<to&&!found;j++){size_t n;const unsigned char *l=reading_lemma(&db->items[j],'V',&n);if(l&&same_text(l,n,p,m))found=1;}
  free(p);return found;
}
/* Append to out every lemma of class cls not yet in seen, each after `;`
 * (the first without it when lead is set). */
static void append_readings(Records *db,size_t from,size_t to,unsigned char cls,unsigned char *out,size_t *len,
                            const unsigned char **seen,size_t *seen_len,size_t *seen_count,int lead) {
  for(;;) {
    const Record *best=NULL;const unsigned char *best_lemma=NULL;size_t best_n=0;
    for(size_t j=from;j<to;j++) {
      const Record *r=&db->items[j];size_t n;const unsigned char *l=reading_lemma(r,cls,&n);
      if(!l||partner_listed(db,from,to,r))continue;
      int dup=0;for(size_t s=0;s<*seen_count&&!dup;s++)if(same_text(l,n,seen[s],seen_len[s]))dup=1;
      if(dup)continue;
      if(!best||reading_before(r,best)){best=r;best_lemma=l;best_n=n;}
    }
    if(!best)return;
    if(!lead)out[(*len)++]=';';lead=0;
    memcpy(out+*len,best_lemma,best_n);*len+=best_n;
    seen[*seen_count]=best_lemma;seen_len[(*seen_count)++]=best_n;
  }
}
static void merge_readings(Records *db) {
  qsort(db->items,db->count,sizeof(Record),record_compare);
  size_t kept=0,dropped=0;
  for(size_t i=0;i<db->count;) {
    size_t end=i+1;while(end<db->count&&!key_compare(&db->items[end],db->items[i].key,db->items[i].key_len))end++;
    Record head=db->items[i];const unsigned char *v=head.value;size_t vn=head.value_len;
    unsigned char first=vn?v[0]:0;
    int mergeable=end-i>1&&vn>1&&strchr("VeZzGENnAD",first)&&!memchr(v,'/',vn)&&!memchr(v,'W',vn)&&!memchr(v,';',vn)&&!memchr(v,'{',vn);
    /* An others.tsv word (WDнад) takes the key's other such words: WDнад;вверху. */
    int composite=end-i>1&&vn>2&&v[0]=='W'&&v[1]=='D'&&lemma_ok(v+2,vn-2);
    if(composite) {
      size_t cap=vn;for(size_t j=i;j<end;j++)cap+=db->items[j].value_len+1;
      unsigned char *out=allocate(cap);size_t len=vn;memcpy(out,v,vn);
      const unsigned char **seen=allocate((end-i+1)*sizeof *seen);size_t *seen_len=allocate((end-i+1)*sizeof *seen_len),seen_count=1;
      seen[0]=out+2;seen_len[0]=vn-2;
      append_readings(db,i,end,'w',out,&len,seen,seen_len,&seen_count,0);
      free(head.value);head.value=out;head.value_len=len;free(seen);free(seen_len);
    } else if(mergeable) {
      size_t cap=vn+16;for(size_t j=i;j<end;j++)cap+=db->items[j].value_len+3;
      unsigned char *out=allocate(cap);size_t len=0,p=0;int ok=1;
      const unsigned char **seen=allocate((end-i)*2*sizeof *seen);size_t *seen_len=allocate((end-i)*2*sizeof *seen_len),seen_count=0;
      out[len++]=v[p++];while(p<vn&&v[p]>='0'&&v[p]<='9')out[len++]=v[p++];
      size_t prefix=len;int plain=1;
      unsigned char cls=strchr("VeZzGE",first)?'V':first;
      if(p>=vn)ok=0;
      /* After Z and its digits the verb is either bare (Z01стремиться) or
       * marked (ZV.закрывать). */
      else if(!is_lemma_run(v[p])) {
        if(!strchr("VeNnAD",v[p]))ok=0;
        else{cls=v[p]=='e'?'V':v[p];out[len++]=v[p++];if(p<vn&&v[p]=='.')out[len++]=v[p++];plain=0;}
      }
      while(ok) {
        size_t start=p;while(p<vn&&is_lemma_run(v[p]))p++;
        if(p==start){ok=0;break;}
        size_t at=len;memcpy(out+len,v+start,p-start);len+=p-start;
        seen[seen_count]=out+at;seen_len[seen_count++]=p-start;
        append_readings(db,i,end,cls,out,&len,seen,seen_len,&seen_count,0);
        if(p>=vn||v[p]=='\\')break;
        plain=0;
        unsigned char next=v[p];
        if(!strchr("VeNnAD",next)){ok=0;break;}
        out[len++]=v[p++];if(p<vn&&v[p]=='.')out[len++]=v[p++];
        cls=next=='e'?'V':next;
      }
      if(ok) {
        int single=plain;
        /* A one-class record that gained readings takes LTGOLD's dotted form
         * (Nстол -> NN.стол;таблица, V11соглашаться -> V11V.соглашаться;…). */
        int dotted=single&&strchr("VeNnAD",first)&&len>p;
        unsigned char *final=allocate(len+(vn-p)+2);size_t fl=prefix;memcpy(final,out,prefix);
        if(dotted){final[fl++]=first=='e'?'V':first;final[fl++]='.';}
        memcpy(final+fl,out+prefix,len-prefix);fl+=len-prefix;
        memcpy(final+fl,v+p,vn-p);fl+=vn-p;
        if(!dotted&&same_text(final,fl,v,vn))free(final);
        else{free(head.value);head.value=final;head.value_len=fl;}
      }
      free(out);free(seen);free(seen_len);
    } else if(!composite)dropped+=end-i-1;
    for(size_t j=i+1;j<end;j++){free(db->items[j].key);free(db->items[j].value);}
    db->items[kept++]=head;i=end;
  }
  db->count=kept;
  fprintf(stderr,"merge_readings: %zu readings of unmergeable records dropped\n",dropped);
}

static void add_people_plural(Records *rus) {
  /* LTPRO stores this suppletive plural as its own noun, paradigm 30. */
  static const unsigned char key[]={0xab,0xee,0xa4,0xa8}; /* люди */
  static const unsigned char code[]={'N',0xd2,0x88,0x9e};
  add_record(rus,key,sizeof key,code,sizeof code);
}

static void add_curated_nouns(Records *rus) {
  /* The source's others.tsv has only the interjection спасибо. Its nominal
   * use (большое спасибо) is neuter and indeclinable, like native шоссе.
   * 0xff is the native no-declension paradigm, not a frozen phrase reading. */
  size_t length; unsigned char *key=to_cp866("спасибо",&length);
  static const unsigned char code[]={'N',0xc0,0x80,0xff};
  add_record(rus,key,length,code,sizeof code);free(key);
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
  if(argc!=6&&argc!=7)fail("usage: openrussian_db build SOURCE_DIR OUTPUT.DIC OUTPUT.RUS OUTPUT.MORPH [FIT.tsv]");
  if(argc==7)load_fits(argv[6]);
  const char *dir=argv[2];size_t need=strlen(dir)+64;char *path=allocate(need);Records source_dic={0},source_rus={0},morph={0};
  /* The demo's closed-class and common-verb readings must outrank unrelated
   * homonyms that become visible when importing the complete tables. */
  add_utf8_record(&source_dic,"a","T");add_utf8_record(&source_dic,"an","T");add_utf8_record(&source_dic,"the","T");
  add_utf8_record(&source_dic,"i","R011я");
  add_utf8_record(&source_dic,"want","V21хотеть");add_utf8_record(&source_dic,"wants","vхотеть");
  add_utf8_record(&source_dic,"can","e00мочь");
  snprintf(path,need,"%s/../lexemes.tsv",dir);load_attributes(path,1);
  snprintf(path,need,"%s/../words.tsv",dir);load_attributes(path,0);
  snprintf(path,need,"%s/verbs.tsv",dir);load_verbs(path);
  snprintf(path,need,"%s/others.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"other");
  snprintf(path,need,"%s/nouns.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"noun");
  snprintf(path,need,"%s/verbs.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"verb");
  snprintf(path,need,"%s/adjectives.tsv",dir);import_file(&source_dic,&source_rus,&morph,path,"adjective");
  add_s_form_homographs(&source_dic);
  add_inflected_homographs(&source_dic,"ing",'G',"N");
  add_inflected_homographs(&source_dic,"ed",'E',"A");
  add_verb_noun_homographs(&source_dic);
  add_native_suffix_gaps(&source_dic);
  merge_readings(&source_dic);
  add_people_plural(&source_rus);add_curated_nouns(&source_rus);emit_morphology_patterns(&morph);
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
/* A theme dictionary (a .txt in openrussian/themes): UTF-8 `key*code` rows, the
 * same codes as BASE.DIC, compiled to an indexed .DIC the engine loads with
 * --dic-overlay. LTGOLD shipped BUSINESS.DIC and COMPUTER.DIC this way. */
static void command_text(const char *input,const char *output) {
  FILE *file=fopen(input,"r");if(!file){perror(input);exit(1);}char *line=NULL;size_t cap=0;Records db={0};
  while(getline(&line,&cap,file)>=0) {
    size_t n=strcspn(line,"\r\n");line[n]=0;if(!n||line[0]=='#')continue;
    char *star=strchr(line,'*');if(!star||star==line||!star[1]){fprintf(stderr,"%s: expected headword*code: %s\n",input,line);exit(1);}
    *star=0;add_utf8_record(&db,line,star+1);
  }
  free(line);fclose(file);if(!db.count)fail("no dictionary rows");
  write_dictionary(output,&db,"ERS",26);printf("wrote %zu records to %s\n",db.count,output);
}

int main(int argc,char **argv) {
  if(argc<2)fail("usage: openrussian_db build|info|find ...");
  if(!strcmp(argv[1],"build"))command_build(argc,argv);
  else if(!strcmp(argv[1],"info")&&argc==3)command_info(argv[2]);
  else if(!strcmp(argv[1],"find")&&argc==4)command_find(argv[2],argv[3]);
  else if(!strcmp(argv[1],"text")&&argc==4)command_text(argv[2],argv[3]);
  else fail("usage: openrussian_db build SOURCE_DIR OUTPUT.DIC OUTPUT.RUS OUTPUT.MORPH | text ENTRIES.txt OUTPUT.DIC | info FILE | find FILE HEADWORD");
  return 0;
}
