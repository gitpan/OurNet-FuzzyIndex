#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "avltree.c"
#include "parse.c"

static SV *  _cb_fn      = (SV*)NULL;
static SV *  _cb_arg1    = (SV*)NULL;
static SV *  _cb_arg2    = (SV*)NULL;
static SV *  _cb_freq    = (SV*)NULL;
static SV *  _cb_obj     = (SV*)NULL;
static HV *  _cb_hash    = (HV*)NULL;
static UV    _cb_weight  = 0;
static UV    _cb_mod     = 0;
static UV    _cb_min     = 0;
static UV    _cb_max     = 0;

static void
hash_cb(key, keylen, freq)
char * key;
char * keylen;
unsigned int freq;
{
    hv_store(_cb_hash, key, (U32)keylen, newSVuv(freq), 0);
}

static void
hashi_cb(key, keylen, freq)
char * key;
char * keylen;
unsigned int freq;
{
    freq *= _cb_weight;
    freq += SvUV(hv_fetch(_cb_hash, key, (U32)keylen, 1)[0]);

    hv_store(_cb_hash, key, (U32)keylen, newSVuv(freq > 0xa3 ? 0xa3 : freq), 0);
}

static void
hashm_cb(key, keylen, freq)
char * key;
char * keylen;
unsigned int freq;
{
    if ((((unsigned int)key[1] % _cb_mod) >= _cb_min) &&
        (((unsigned int)key[1] % _cb_mod) <= _cb_max))
    hv_store(_cb_hash, key, (U32)keylen, newSVuv(freq), 0);
}

static void
hashim_cb(key, keylen, freq)
char * key;
char * keylen;
unsigned int freq;
{
    if ((((unsigned int)key[1] % _cb_mod) >= _cb_min) &&
        (((unsigned int)key[1] % _cb_mod) <= _cb_max)) {
        freq *= _cb_weight;
        freq += SvUV(hv_fetch(_cb_hash, key, (U32)keylen, 1)[0]);
        hv_store(_cb_hash, key, (U32)keylen, newSVuv(freq > 0xa3 ? 0xa3 : freq), 0);
    }
}


static void
insert_cb(arg1, arg2, arg2len)
char * arg1;
char * arg2;
unsigned int arg2len;
{
    dSP ;
        PUSHMARK(SP) ;

        EXTEND(SP, 3);

        sv_setpv( _cb_arg1, arg1);
        sv_setpvn(_cb_arg2, arg2, arg2len);

        PUSHs(_cb_obj);
        PUSHs(_cb_arg1);
        PUSHs(_cb_arg2);
        /*
        PUSHs(sv_2mortal(newSVpv(arg1, 0)));
        PUSHs(sv_2mortal(newSVpv(arg2, arg2len)));
        */

        PUTBACK ;
        /* Call the Perl sub to process the callback */
        call_method("DB_File::put", G_DISCARD) ;

}

static void
insertm_cb(arg1, arg2, arg2len)
char * arg1;
char * arg2;
unsigned int arg2len;
{
    if ((((unsigned int)arg1[1] % _cb_mod) >= _cb_min) &&
        (((unsigned int)arg1[1] % _cb_mod) <= _cb_max)) {

    dSP ;
        PUSHMARK(SP) ;

        EXTEND(SP, 3);

        sv_setpv( _cb_arg1, arg1);
        sv_setpvn(_cb_arg2, arg2, arg2len);

        PUSHs(_cb_obj);
        PUSHs(_cb_arg1);
        PUSHs(_cb_arg2);

        PUTBACK ;
        /* Call the Perl sub to process the callback */
        perl_call_pv("DB_File::put", G_DISCARD) ;
    }
}


static void
delim_cb(arg1, arg2, arg2len)
char * arg1;
char * arg2;
unsigned int arg2len;
{
    dSP ;
        PUSHMARK(SP) ;

        EXTEND(SP, 2);

        sv_setpv( _cb_arg1, arg1);
        sv_setpvn(_cb_arg2, arg2, arg2len);

        PUSHs(_cb_arg1);
        PUSHs(_cb_arg2);

        PUTBACK ;

        /* Call the Perl sub to process the callback */
        perl_call_sv(_cb_fn, G_DISCARD) ;

}

/* XXX won't work just now */
static void
delim_q_cb(arg1, arg2, arg2len)
char * arg1;
char * arg2;
unsigned int arg2len;
{
    dSP ;
        PUSHMARK(SP) ;

        EXTEND(SP, 2);

        sv_setpv( _cb_arg1, arg1);
        sv_setpvn(_cb_arg2, arg2, arg2len);

        PUSHs(_cb_arg1);
        PUSHs(_cb_arg2);

        PUTBACK ;
}


static void
pair_cb(key, val, freq)
char  * key;
char  * val;
unsigned int freq;
{
    dSP ;

        PUSHMARK(SP) ;

        EXTEND(SP, 3);

        sv_setpv( _cb_arg1, key);
        sv_setpvn(_cb_arg2, val, 2);
        sv_setuv( _cb_freq, freq);

        PUSHs(_cb_arg1);
        PUSHs(_cb_arg2);
        PUSHs(_cb_freq);

        PUTBACK ;

        /* Call the Perl sub to process the callback */
        perl_call_sv(_cb_fn, G_DISCARD) ;
}

MODULE = OurNet::FuzzyIndex		PACKAGE = OurNet::FuzzyIndex
PROTOTYPES: ENABLE

void
_parse_d(strref, seed, fn)
	SV   *  strref
	char *  seed
    SV   *  fn
  CODE:
    /* Remember the Perl sub */
    if (_cb_fn == (SV*)NULL)
        _cb_fn = newSVsv(fn);
    else
        SvSetSV(_cb_fn, fn);

    if (_cb_arg1 == (SV*)NULL) {
        _cb_arg1 = newSVpv("", 0);
        _cb_arg2 = newSVpv("", 0);
    }

    /* register the callback with the external library */
    parse_delim(SvPVX(SvRV(strref)), seed, (PARSE_CB *)delim_cb);


void
_parse_q(strref, seed, fn)
	SV   *  strref
	char *  seed
    SV   *  fn
  CODE:
    query = 1;

    if (_cb_fn == (SV*)NULL)
        _cb_fn = newSVsv(fn);
    else
        SvSetSV(_cb_fn, fn);

    if (_cb_arg1 == (SV*)NULL) {
        _cb_arg1 = newSVpv("", 0);
        _cb_arg2 = newSVpv("", 0);
    }

    /* XXX delim_q_cb won't work just now */
    /* register the callback with the external library */
    parse_delim(SvPVX(SvRV(strref)), seed, (PARSE_CB *)delim_cb);
    query = 0;


void
_parse_p(strref, fn)
	SV   *  strref
    SV   *  fn
  CODE:
    /* Remember the Perl sub */
    if (_cb_fn == (SV*)NULL)
        _cb_fn = newSVsv(fn);
    else
        SvSetSV(_cb_fn, fn);

    if (_cb_arg1 == (SV*)NULL) {
        _cb_arg1 = newSVpv("", 0);
        _cb_arg2 = newSVpv("", 0);
    }

    if (_cb_freq == (SV*)NULL) {
        _cb_freq = newSVuv(0);
    }

    /* register the callback with the external library */
    parse_pair(SvPVX(SvRV(strref)), (PARSE_CB *)pair_cb);


void
_parse(strref, hashref, weight, mod, min, max)
	SV   *  strref
	SV   *  hashref
	IV      weight
	IV      mod
	IV      min
	IV      max

  CODE:
    _cb_weight = weight ? (UV)weight : 1;

    if (mod) {
        _cb_mod = (UV)mod;
        _cb_min = (UV)min;
        _cb_max = (UV)max;
    }

    if (SvROK(hashref) && SvTYPE(SvRV(hashref)) == SVt_PVHV) {
        /* complex case */
        _cb_hash = (HV*)SvRV(hashref);
        parse_word(SvPVX(SvRV(strref)), mod ? (PARSE_CB *)hashim_cb : (PARSE_CB *)hashi_cb );
    }
    else if (_cb_weight != 1) {
        /* complex case */
        sv_setsv(hashref, newRV_inc((struct sv *)(_cb_hash = newHV())));
        parse_word(SvPVX(SvRV(strref)), mod ? (PARSE_CB *)hashim_cb : (PARSE_CB *)hashi_cb );
    }
    else {
        /* simple case */
        sv_setsv(hashref, newRV_inc((struct sv *)(_cb_hash = newHV())));
        parse_word(SvPVX(SvRV(strref)), mod ? (PARSE_CB *)hashm_cb : (PARSE_CB *)hash_cb );
    }

  OUTPUT:
    hashref

void
_insert(strref, seed, objref, mod, min, max)
	SV   *  strref
	char *  seed
	SV   *  objref
	IV      mod
	IV      min
	IV      max

  CODE:
    /* Remember the Perl sub */

    if (mod) {
        _cb_mod = (UV)mod;
        _cb_min = (UV)min;
        _cb_max = (UV)max;
    }

    if (_cb_arg1 == (SV*)NULL) {
        _cb_arg1 = newSVpv("", 0);
        _cb_arg2 = newSVpv("", 0);
    }

    if (_cb_obj == (SV*)NULL)
        _cb_obj = newSVsv(objref);
    else
        sv_setsv_mg(_cb_obj, objref);

    /* register the callback with the external library */
    parse_delim(SvPVX(SvRV(strref)), seed, mod ? (PARSE_CB *)insertm_cb : (PARSE_CB *)insert_cb);
