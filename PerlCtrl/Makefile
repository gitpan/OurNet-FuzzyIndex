PROGNAME=HelloCtrl

all:
    perlctrl -c HelloCtrl.pl

clean:
    del $(PROGNAME).obj
    del vc50.pch

realclean: clean
    del $(PROGNAME).dll

test:
    regsvr32 $(PROGNAME)
    Hello.vbs

