#!/usr/bin/perl

require 5.005;

use ExtUtils::MakeMaker;

WriteMakefile(
    AUTHOR          => 'Autrijus Tang (autrijus@autrijus.org)',
    ABSTRACT        => 'Inverted search for double-byte characters',
	NAME            => 'OurNet::FuzzyIndex',
	VERSION_FROM    => 'FuzzyIndex.pm',
    XSPROTOARG      => '-noprototypes',
    DISTNAME        => 'OurNet-FuzzyIndex',
    BINARY_LOCATION => 'x86/OurNet-FuzzyIndex.tar.gz',

    PREREQ_PM       => {
        DB_File     => '1.72',       # FuzzyIndex
    },

    EXE_FILES       => [ <bin/*> ],

    dist            => {
        COMPRESS    => 'gzip',
        SUFFIX      => '.gz',
    }
);

# Fix a bug for Win95 nmake
if ($^O =~ /Win32/ and -e 'Makefile') {
    local $/;
    open _, 'Makefile';
    my $content = <_>;
    $content =~ s/\n\@\[\n/\n/g;
    $content =~ s/\n\]\n/\n\n/g;
    close _;
    open _, '>Makefile' or exit;
    print _ $content;
}


