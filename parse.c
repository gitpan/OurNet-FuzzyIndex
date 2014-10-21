#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "avltree.h"

#define is_big5(p)	    ((unsigned int)*(p) > 0xa0)
#define is_big5word(p)	((unsigned int)*(p) > 0xa3)
#define is_alnum(p)     ((*(p) > 0x60) && (*(p) < 0x7b)) || ((*(p) > 0x40) && (*(p) < 0x5b)) || ((*(p) > 0x30) && (*(p) < 0x3b))

#define MAXKEY  (32)
#define MAXVAL  (32768)
#define PARSE_SINGLE_CHARACTER

struct entry {
    char *word;
    unsigned int freq;
};

char key[MAXKEY];
char val[MAXVAL];
char delim[4] = "????";
char *valp = val;
char query;

struct entry *last;

tree *wordtree;

typedef void PARSE_CB(char *, char *, unsigned int);

PARSE_CB *cb;
/* void(*cb)(char *arg1, char *arg2, unsigned int arg3); */


int
cb_delim(struct entry *en)
{
    if(is_big5(en->word)) {
	    if(last) {
	        if((*(en->word) == *(last->word)) && (*(en->word+1) == *(last->word+1))) {
#ifdef PARSE_DEBUG
	            printf("[strncmp(%2.2s, %2.2s)]\n", en->word, last->word);
            	printf("Append Val: [%2.2s]\n", en->word+2);
#endif
	            memcpy(valp+1, en->word+2, 2);
	            *(valp+=3) = (en->freq > 0xa3 ? 0xa3 : en->freq);
	        }
	        else {
                cb(key, val, valp-val+1);
#ifdef PARSE_DEBUG
                printf("From Scratch: [%s]\n", en->word);
#endif
    	        memcpy(key, en->word, 2);
    	        key[2]=0;
                memcpy(valp = val, delim, 4);
                memcpy(valp+4, en->word+2, 2);
                *(valp+=6) = (en->freq > 0xa3 ? 0xa3 : en->freq);
    	    }
    	}
	    else {
#ifdef PARSE_DEBUG
        	printf("True Scratch: [%s]\n", en->word);
#endif
	        memcpy(key, en->word, 2);
	        key[2]=0;
            memcpy(valp = val, delim, 4);
            memcpy(valp+4, en->word+2, 2);
            *(valp+=6) = (en->freq > 0xa3 ? (char)0xa3 : en->freq);
	    }
        last = en;
	}
	else {
        memcpy(valp = val, delim, 4);
	    *(valp+4)  = 0x20;
	    *(valp+5)  = 0x20;
	    *(valp+=6) = (en->freq > 0xa3 ? (char)0xa3 : en->freq);

	    cb(en->word, val, valp-val+1);
    }

	return 1;
}

int
cb_pair(struct entry *en)
{
    if(is_big5(en->word)) {
        memcpy(key, en->word, 2);
        key[2]=0;
        cb(key, en->word+2, en->freq > 0xa3 ? 0xa3 : en->freq);
	}
	else {
        cb(en->word, "  ", en->freq > 0xa3 ? 0xa3 : en->freq);
    }

	return 1;
}

int
cb_word(struct entry *en)
{
    if(is_big5(en->word)) {
        cb(en->word, (char *)4, en->freq > 0xa3 ? 0xa3 : en->freq);
	}
	else {
        cb(strcat(en->word, "  "), (char *)strlen(en->word)+2, en->freq > 0xa3 ? 0xa3 : en->freq);
    }

	return 1;
}

int
wordcmp(struct entry *a, struct entry *b)
{
    return strcmp(a->word, b->word);
}


void
addentry(char *x)
{
	struct entry *en, k;
    k.word = x;
    if((en = tree_srch(&wordtree, (BTREE_CMP *)wordcmp, &k))) {
	    ++en->freq;
    }
    else {
        en = (struct entry *)malloc(sizeof(struct entry));
        en->word = strdup(x);
        en->freq = 1;
        tree_add(&wordtree, (BTREE_CMP *)wordcmp, en, 0);
    }
}

void
en_cleanup(struct entry *en)
{
    free(en);
}

void extract_words(unsigned char *p) {
	tree_init(&wordtree);

    /* autrijus 8/20: fixed null-termination, increased performance */

    while(*p) {
    	if(is_big5(p)) {
    	    if(is_big5word(p += 2)) {
        		key[4] = 0;
        		if(is_big5word(p - 2)) {
        		    strncpy(key, p-2, 4);
        		    addentry(key);
        		}

        		while(is_big5word(p += 2)) {
        		    strncpy(key, p-2, 4);
        		    addentry(key);
        		}

#ifdef PARSE_SINGLE_CHARACTER
    	    /* autrijus 7/17: add single-letter handling */
    	        /* autrijus 9/23: optimization for queries */
     	        if (!(query && is_big5word(p-4))) {
            		key[2] = key[3] = 0x21;
            		strncpy(key, p-2, 2);
            		addentry(key);
            	}

    	    }
    		else if(is_big5word(p - 2)) {
    		    key[4] = 0;
    		    key[2] = key[3] = 0x21;
    		    strncpy(key, p - 2, 2);
    		    addentry(key);
    		/* end autrijus */
#endif
    		}
    	}
    	else if(is_alnum(p)) {
    	    char *start = p;
    	    int xlen = 0;
    	    do {
    	        if((*(p) > 0x40) && (*(p) < 0x5b)) *(p) += 32;
        		++p, ++xlen;
    	    }
    	    while(is_alnum(p));

    	    if(xlen > 1) {
    	        if(xlen > MAXKEY) xlen = MAXKEY;
    	        strncpy(key, start, xlen);
    	        key[xlen] = 0;
        		addentry(key);
    	    }
    	}
    	else {
    	    ++p;
    	}
    }
}

void parse_delim (unsigned char *p,
                  char *seed,
                  PARSE_CB * callback){
    extract_words(p);
    memcpy(delim, seed, 4);

    last = 0;
    cb = callback;

 	tree_trav(&wordtree, (BTREE_UAR *)cb_delim);

    if (last) {
        last->word[2] = 0;
        cb(last->word, val, valp-val+1);
    }
    tree_mung(&wordtree, (BTREE_UAR *)en_cleanup);
}

void parse_pair (unsigned char *p, PARSE_CB * callback){
    extract_words(p);

    cb = callback;
	tree_trav(&wordtree, (BTREE_UAR *)cb_pair);
    tree_mung(&wordtree, (BTREE_UAR *)en_cleanup);
}


void parse_word (unsigned char *p, PARSE_CB * callback){
    extract_words(p);

    cb = callback;
	tree_trav(&wordtree, (BTREE_UAR *)cb_word);
    tree_mung(&wordtree, (BTREE_UAR *)en_cleanup);
}



#ifdef PARSE_MAIN

void default_cb(char *arg1, char *arg2) {
    printf("(%s - %s)\n", arg1, arg2+4);
}

int main() {
    return extract_words("�D�i�D�D�`�D�W�i�W�D�`�W�L�W�U���l���W�Ѧa��", default_cb);
}

#endif
