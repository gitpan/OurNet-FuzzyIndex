package OurNet::ChatBot;
require 5.005;

$OurNet::ChatBot::VERSION = '1.2';

use strict;
use lib qw/./;

use OurNet::FuzzyIndex;

=head1 NAME

OurNet::ChatBot - Context-free interactive Q&A engine

=head1 SYNOPSIS

    use OurNet::ChatBot;

    $mybot = OurNet::ChatBot->new('Amber', 'Amber.bot', 0);

    while (1) {
        print 'User: ';
        print 'Amber Bot: '.$mybot->input(<STDIN>)."\n";
    }

=head1 DESCRIPTION

The ChatBot module simulates a general-purpose, context-free,
interactive Chat Bot using the OurBot(tm) engine. It reads
the file stored in ChatBot/ directory, parses synonyms and
random output settings, then return answers via the input()
method.

The lastone property is used to return/set the id of the bot's
last sentence. In conjunction of directly manipulating the CHUNKS
array (which contains all possible return values for input()),
the front-end program could prevent duplicate responses.

=head1 CAVEATS

The nextone flag-property is badly implemented.

=cut

# ---------------
# Variable Fields
# ---------------
use fields qw/botfile botname writable db nextone
              avoid synonyms rndouts lastone/;

# ---------------------------------------
# Subroutine new($botname,$bot,$writable)
# ---------------------------------------
# Input:  Bot name, BotDB, Writeable Flag
# Output: A ChatBot object
# ---------------------------------------
sub new {
    my $self = fields::new(shift);

    $self->{'botname'}  = shift;
    $self->{'botfile'}  = shift
        or (warn("OurNet::ChatBot needs a bot"), return);
    $self->{'writable'} = shift;

    my $botfile = '';

    foreach my $botdir (@INC) {
        last if -e ($botfile = "$botdir/$self->{'botfile'}");
        last if -e ($botfile = "$botdir/Chatbot/$self->{'botfile'}");
        last if -e ($botfile = "$botdir/Amber/$self->{'botfile'}");
    }

    $botfile = $self->{'botfile'} if -e $self->{'botfile'};

    unless (-e $botfile) {
        die("OurNet::ChatBot cannot find the database: $self->{'botfile'}")
            unless $self->{'writable'};
        $botfile = $self->{'botfile'};
    }

    $self->{'db'}       = OurNet::FuzzyIndex->new($botfile);
    $self->{'synonyms'} = [split(/\n/, $self->{'db'}->getvar('synonyms') || '')];
    $self->{'rndouts'}  = [split(/\n/, $self->{'db'}->getvar('rndouts')  || '')]
                          || ['...'];

    return $self;
}

# --------------------------------------
# Subroutine addsyn($self, $skey, @syns)
# --------------------------------------
# Input:  Object, Word, Synonyms
# --------------------------------------
sub addsyn {
    my $self = shift;
    my $skey = shift;

    push(@{$self->{'synonyms'}}, $skey || ' ', join('|', @_));
}

# ------------------------------------------------
# Subroutine addentry($self, $content, [$trigger])
# ------------------------------------------------
# Input:  Object, Text Chunk
# ------------------------------------------------
sub addentry {
    my $self    = shift;
    my $content = shift;
    # my %words   = $self->{'db'}->parse_xs($content);

    return unless $self->{'writable'};

    # while (my $weight = shift) {
        # %words = $self->{'db'}->parse_xs(shift, $weight, \%words);
    # }

    # $self->{'db'}->insert($content, \%words);
    print "."; # print $content."\n";
    $self->{'db'}->insert($content, shift || $content);
}


# -----------------------------------
# Subroutine sync($self)
# -----------------------------------
# Syncronizes with the Database file.
# -----------------------------------
sub sync {
    my $self = shift;

    return unless $self->{'writable'};

    $self->{'db'}->setvar('synonyms', join("\n", @{$self->{'synonyms'}}));
    $self->{'db'}->setvar('rndouts', join("\n", @{$self->{'rndouts'}}));
    $self->{'db'}->sync;
}

# -------------------------------------
# Subroutine input($self, $say, @avoid)
# -------------------------------------
# Input:  Object, Input, Chunks to skip
# Output: ChatBot's feedback
# -------------------------------------
sub input {
    my $self    = shift;
    my $say     = shift;
    my $avoid   = join(',', ($self->{'avoid'} || '', @_ || '', ''));

    # Substitute synonyms
    foreach my $synline (0 .. (($#{$self->{'synonyms'}} - 1) / 2)) {
        $say =~ s{$self->{'synonyms'}[$synline * 2 + 1]}
                 {$self->{'synonyms'}[$synline * 2]}g;
    }

    my %matched = $self->{'db'}->query("$say\xa4\x3f", $MATCH_PART);

    foreach my $match (sort {$matched{$b} <=> $matched{$a}} keys(%matched)) {
        my $num = unpack('N', $match);
        next if index($avoid, ",$num,") > -1;

        $self->{'lastone'} = $num;
        $self->{'avoid'}  .= ",$num";

        return $self->{'db'}->getkey($self->{'nextone'}
            ? pack('N', ($num % $self->{'db'}->{'idxcount'}) + 1)
            : $match);
    }

    return $self->{'rndouts'}[ int(rand() * ($#{$self->{'rndouts'}} + 1)) ];
}

# -----------------------------------------------------
# Subroutine convert($self, $data)
# -----------------------------------------------------
# Converts Chatbot::Amber bot file entries to database.
# -----------------------------------------------------
sub convert {
    my $self = shift;
    my ($init, @chunks) = split(/\015?\012\s*--+\s*\015?\012/, shift);
    my ($def_val);

    foreach my $line ($init =~ m/^SYN \[(.*)\]/gm) {
        if ($line =~ m/^(.*)\s?::\s?(.+)/) {
            push(@{$self->{'synonyms'}}, $1 || ' ',
                 join('|', split(/\\\s/, '('.quotemeta($2).')')));
        }
    }

    if ($init =~ m/^RND \[(.*)\]/m) {
        @{$self->{'rndouts'}} = split(/\s+/, $1);
    }

    if ($init =~ m/^DEV \[(\d+)\]/m) {
        $def_val = $1;
    }

    $self->sync();

    foreach my $chunk (@chunks) {
        my @keywords;

        while ($chunk =~ s/^#(\d*)(.*)//gm) {
            push @keywords, $1 || $def_val;
            push @keywords, $2;
        }

        while ($chunk =~ s/^(.{52,})\n+/$1/g) {};

        $self->addentry($chunk, @keywords);
    }
}

1;

__END__

=head1 SEE ALSO

L<OurNet::FuzzyIndex>

=head1 AUTHORS

Autrijus Tang E<lt>autrijus@autrijus.org>

=head1 COPYRIGHT

Copyright 2001 by Autrijus Tang E<lt>autrijus@autrijus.org>.

All rights reserved.  You can redistribute and/or modify
this module under the same terms as Perl itself.

=cut
