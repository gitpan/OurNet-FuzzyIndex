#!/usr/bin/perl
# $File: //depot/OurNet-FuzzyIndex/Makefile.PL $ $Author: autrijus $
# $Revision: #5 $ $Change: 2149 $ $DateTime: 2001/10/18 21:43:43 $

require 5.005;

use ExtUtils::MakeMaker;

WriteMakefile(
    AUTHOR		=> 'Autrijus Tang (autrijus@autrijus.org)',
    ABSTRACT		=> 'Inverted search for double-byte characters',
    NAME		=> 'OurNet::FuzzyIndex',
    VERSION_FROM	=> 'FuzzyIndex.pm',
    XSPROTOARG		=> '-noprototypes',
    DISTNAME		=> 'OurNet-FuzzyIndex',
    BINARY_LOCATION	=> 'x86/OurNet-FuzzyIndex.tar.gz',

    PREREQ_PM		=> {
        DB_File		=> '1.54', # FuzzyIndex
    },

    EXE_FILES		=> [ <bin/*> ],

    dist		=> {
        COMPRESS	=> 'gzip',
        SUFFIX		=> '.gz',
    }
);
