package OurNet::FuzzyIndex;
require 5.005;

$OurNet::FuzzyIndex::VERSION = '1.5';

use strict;
use integer;
use DB_File qw/$DB_BTREE/;
use base qw/DynaLoader Exporter/;

bootstrap OurNet::FuzzyIndex $OurNet::FuzzyIndex::VERSION;

=head1 NAME

OurNet::FuzzyIndex - Inverted search for double-byte characters

=head1 SYNOPSIS

    use OurNet::FuzzyIndex;

    my $idxfile  = 'test.idx'; # Name of the database file
    my $pagesize = undef;      # Page size (twice of an average record)
    my $cache    = undef;      # Cache size (undef to use default)
    my $subdbs   = 0;          # Number of child dbs; 0 for none

    # Initiate the DB from scratch
    unlink $idxfile if -e $idxfile;
    my $db = OurNet::FuzzyIndex->new($idxfile, $pagesize, $cache, $subdbs);

    # Index a record: key = 'Doc1', content = 'Some text here'
    $db->insert('Doc1', 'Some text here');

    # Alternatively, parse the content first with different weights
    my %words = $db->parse("Some other text here", 5);
    %words = $db->parse_xs("Some more texts here", 2, \%words);

    # Then index the resulting hash with 'Doc2' as its key
    $db->insert('Doc2', %words);

    # Perform a query: the 2nd argument is the 'exact match' flag
    my %result = $db->query('search for some text', $MATCH_FUZZY);

    # Combine the result with another query
    %result = $db->query('more please', $MATCH_NOT, \%result);

    # Dump the results; note you have to call $db->getkey each time
    foreach my $idx (sort {$result{$b} <=> $result{$a}} keys(%result)) {
        $val = $result{$idx};
        print "Matched: ".$db->getkey($idx)." (score $val)\n";
    }

    # Set database variables
    $db->setvar('variable', "fetch success!\n");
    print $db->getvar('variable');

    # Get all records: the optional 0 says we want an array of keys
    print "These records are indexed:\n";
    print join(',', $db->getkeys(0));

    # Alternatively, get it with its internal index number
    my %allkeys = $db->getkeys(1);

=head1 DESCRIPTION

OurNet::FuzzyIndex implements a simple consecutive-letter indexing
mechanism specifically designed for multi-byte encoding maps, e.g.
big-5 or utf8.

It uses DB_File to create an associative mapping from each character
to its consecutive one, utilizing DB_BTREE's duplicate key feature
to speed up the query time. Its scoring algorithm is also geared to
reduce redundant word's impact on the query's result.

Although this module currently only supports big-5 and latin-1 encodings
internally, you could override the C<parse.c> module for extensions,
or add your own translation maps.

=head1 KNOWN ISSUES

The C<query()> function uses a time-consuming callback function _parse_q
to parse the query string; it is expected to be changed to a simple
function that returns the whole processed list. (Fortunately, most
query strings won't be long enough to cause significant difference.)

The MATCH_EXACT flag is misleading; FuzzyIndex couldn't tell if a query
matches the conetnt exactly from the info stored in the index file
alone. You are encouraged to write your own grep-like post filter.

=head1 TODO

* Internal handling of locale/unicode mappings
* Boolean / selective search using combined MATCH_* flags
* Fix bugs concerning sub_dbs

=cut

# ---------------
# Variable Fields
# ---------------
use fields qw/dbfile   flag     deleted
              idxcount subcount submod   submin   submax
              obj      db       subobj   subdb/;

# -----------------
# Package Constants
# -----------------
use constant R_DUP       => DB_File::R_DUP();
use constant R_NEXT      => DB_File::R_NEXT();
use constant R_FIRST     => DB_File::R_FIRST();
use constant R_CURSOR    => DB_File::R_CURSOR();
use constant O_RDWR      => DB_File::O_RDWR();
use constant O_RDONLY    => DB_File::O_RDONLY();
use constant O_CREAT     => DB_File::O_CREAT();
use constant DB_VERSION  => $DB_File::db_version;
use constant MEM_WRITE   => 16_000_000;
use constant MEM_READ    => 0;
use constant SCORE_ALL   => 800;
use constant SCORE_EACH  => 200;
use constant SCORE_PART  => 50;
use constant MATCH_EXACT => 1;
use constant MATCH_FUZZY => 0;
use constant MATCH_PART  => -1;
use constant MATCH_NOT   => -2;

use vars qw/$MATCH_EXACT $MATCH_FUZZY $MATCH_PART $MATCH_NOT @EXPORT/;
@EXPORT = qw/$MATCH_EXACT $MATCH_FUZZY $MATCH_PART $MATCH_NOT/;

$MATCH_EXACT = MATCH_EXACT;
$MATCH_FUZZY = MATCH_FUZZY;
$MATCH_PART  = MATCH_PART;
$MATCH_NOT   = MATCH_NOT;

# ------------------------------------------------------------------------
# Subroutine new($dbfile, $pagesize, $cachesize, $split, $submin, $submax)
# ------------------------------------------------------------------------
sub new {
    my $class = shift;
    my $self  = ($] > 5.00562) ? fields::new($class)
                               : do { no strict 'refs';
                                      bless [\%{"$class\::FIELDS"}], $class };

    $self->{dbfile} = shift;
    $self->{flag}   = (-e $self->{dbfile}) ? (-r $self->{dbfile}) ?
                      (-w $self->{dbfile}) ? O_RDWR : O_RDONLY :
                      die("Cannot read main DB: $self->{dbfile}") :
                      (O_RDWR|O_CREAT);

    $DB_BTREE->{psize} = shift || 0;
    $DB_BTREE->{cachesize} = shift || (($self->{flag} == O_RDONLY) ?
                                        MEM_WRITE : MEM_READ) /
      (($self->{subcount}  = shift || 0) + 1);
    $DB_BTREE->{flags}     = R_DUP;

    $self->{obj} = tie(
		%{$self->{db}},
		'DB_File',
		$self->{dbfile},
		$self->{flag},
        $self->{flag} ? 0640 : 0440,
        $DB_BTREE
	) or die "Cannot open main DB: $self->{dbfile}";

    if (exists $self->{db}{_subcount}) {
        $self->{subcount} = $self->{db}{_subcount};
    }
    else {
        $self->_store('_subcount', $self->{subcount});
    }

    if (exists $self->{db}{_deteled}) {
        $self->{deleted}{$_} = '' 
            foreach (split(/(....)/s, $self->{db}{_deleted}));
    }
    else {
        $self->_store('_deleted', '');
        $self->{deleted} = {};
    }

    $self->{submin}   = shift || 0;
    $self->{submax}   = shift || $self->{subcount} - 1;
    $self->{submod}   = (
		$self->{submin} or $self->{submax} >= $self->{subcount}
	) ? $self->{subcount} : 0;

    $self->{idxcount} = $self->{db}{_idxcount} || 0;

    foreach my $num ($self->{submin}..$self->{submax}) {
        $self->{subobj}[$num] = tie (
			%{$self->{subdb}[$num]},
            'DB_File',
            "$self->{dbfile}.$num",
            $self->{flag},
            $self->{flag} ? 0640 : 0440,
            $DB_BTREE
		) or die "Cannot open child DB # $num";
    }

    return $self;
}

sub subval {
    my $self = shift;

    return ($self->{submod}, $self->{submin}, $self->{submax});
}

# ------------------------------------------------------------
# Subroutine parse_xs([$self], $content, [$weight], [\%words])
# ------------------------------------------------------------
sub parse_xs {
    my $self    = UNIVERSAL::isa($_[0], __PACKAGE__) ? shift : undef;
    my $wordref = ref($_[-1]) ? pop : 0;
    local $^W; # no warnings, thank you

    _parse(
        \$_[0], $wordref, ($_[1] || 1),
        ((defined $self) ? $self->subval
                         : (0,0,0))
    );

    return wantarray ? %{$wordref} : $wordref;
}

# ------------------------------------------------------
# Subroutine parse([$self], $content, $weight, [%words])
# ------------------------------------------------------
sub parse {
    my $self    = UNIVERSAL::isa($_[0], __PACKAGE__) ? shift : undef;

    my $weight  = $_[1] || 1;
    my %words   = @_[2..$#_];

    my ($mod, $min, $max) = $self->subval if defined $self;

    my ($lastpos, $strlen, $this, $next) = (0, length($_[0]));

    # Obfuscated Perl Contest entry starts here
    my $_plus = (($weight == 1) ? '++' : "+= $weight");
    my $_incr = $mod ? '(ord(substr(\$this, -1)) % '.$mod.'>'.($min-1).' and'.
                       ' ord(substr(\$this, -1)) % '.$mod.'<'.($max+1).' and'.
                       ' $words{$this}{$next}'.$_plus.'),'.
                       ' $this = $next'
                     : '$words{$this}{$this = $next}'.$_plus;
    eval '
        local $^W;

        while ($lastpos < $strlen) {
            next if ($this = substr($_[0], $lastpos++, 2)) lt "\241" or
                    ($next = substr($_[0], ++$lastpos, 2)) lt "\244";
            '.$_incr.' if ($this gt "\243");
            '.$_incr.'
                while (($next = substr($_[0], $lastpos += 2, 2)) gt "\243");
        }
        while ($_[0] =~ /\w\w/gs) {
            $lastpos =  pos($_[0]) - 2;
            $_[0]    =~ /\G\w*/gs;
            $words{lc(substr($_[0], $lastpos,
                             pos($_[0]) - $lastpos))}{"  "}'.$_plus.'
                if (pos($_[0]) < $lastpos + 40);
        }
    ';

    return wantarray ? %words : \%words;
}

# ----------------------------------------------------
# Subroutine insert($self, $key, [$content | \%words])
# ----------------------------------------------------
sub insert {
    my ($self, $key) = splice(@_, 0, 2);
    local $^W; # no warnings, thank you

    die "Cannot insert into a read-only database"
        if $self->{flag} == O_RDONLY;

    my $id = pack('N', ++$self->{idxcount});

    if (not ref($_[0])) {
        # Callback-based code starts here
        _insert(
            \$_[0], $id, $self->{obj},
            $self->{submod} ? $self->subval
                            : (0,0,0)
        ) if length($_[0]);
    }
    else {
        my $matchref = $_[0];
        my ($entry, $freq, $k, $v);
        my ($lastkey, $lastval);

        if (!$self->{submod}) {
            while (my ($entry, $freq) = each %{$matchref}) {
                if (($v = substr($entry, -2)) eq "  ") {
                    # Latin-1
                    $self->{db}{substr($entry, 0, -2)} = $id."  ".chr($freq);
                }
                elsif (($k = substr($entry, 0, -2)) eq $lastkey) {
                    # Big-5 continued
                    $lastval .= $v.chr($freq);
                }
                else {
                    # Big-5 scratch
                    $self->{db}{$lastkey} = $id.$lastval if $lastkey;
                    $lastkey = $k;
                    $lastval = $v.chr($freq);
                }
            }

            $self->{db}{$lastkey} = $id.$lastval if $lastkey;
        } else {
            my ($mod, $min, $max) = $self->subval;
            my $thismod;

            while (my ($entry, $freq) = each %{$matchref}) {
                $thismod = ord(substr($entry, 1, 1)) % $mod;
                next if ($thismod < $min or
                         $thismod > $max);

                if ($v = substr($entry, -2) eq "  ") {
                    # Latin-1
                    $self->{subdb}[$thismod]{substr($entry, 0, -2)} = 
					    $id."  ".chr($freq);
                }
                elsif (($k = substr($entry, 0, -2)) eq $lastkey) {
                    # Big-5 continued
                    $lastval .= $v.chr($freq);
                }
                else {
                    # Big-5 scratch
                    $self->{subdb}[$thismod]{$lastkey} = $id.$lastval 
						if $lastkey;

                    $lastkey = $k;
                    $lastval = $v.chr($freq);
                }
            }

            $self->{subdb}[$thismod]{$lastkey} = $id.$lastval if $lastkey;
        }
    }

    $self->{db}{"!$id"} = $key if defined $key;
    $self->_store('_idxcount', $self->{idxcount});

    return $id;
}

# -------------------------------------------------
# Subroutine query($self, $query, $flag, [\%match])
# -------------------------------------------------
sub query {
    my $self  = shift;
    my $flag  = $_[1];
    my %match = ref($_[2]) ? %{$_[2]} : ();
    my %matchnext;
    my ($words, @parsed) = 0;
    my ($mod, $min, $max) = $self->subval;
    my $done;

    local $^W; # no warnings, thank you

    _parse_q(\$_[0], '    ', sub  {
        return if $done;
        
        my ($qk, $qv) = @_;

        return if ($mod and (ord(substr($qk, -1)) % $mod < $min or
                             ord(substr($qk, -1)) % $mod > $max));

        my $valp = 1;
        my ($status, $k, $v) = (0, $qk, '');
        my $dbobj = $mod ? $self->{subobj}[ord(substr($qk, -1)) % $mod]
                         : $self->{obj};
        my @matched;

        for ($status = $dbobj->seq($k, $v, R_CURSOR);
    	     $k eq $qk and $status == 0;
             $status = $dbobj->seq($k, $v, R_NEXT)) {
            push @matched, $v;
    	}

        my ($vk, $vv);

        if (@matched) {
            while ($vk = substr($qv, $valp += 3, 2)) {
                my $wordcount = 0;
                $vv = ord(substr($qv, $valp + 2, 1));
                $words += $vv;

                if ($vk eq '!!') {
                    foreach my $match (@matched) {
                        $wordcount += length($match);
                    }

                    foreach my $match (@matched) {
                        my $seq = substr($match, 0, 4);

                        if ($flag == MATCH_EXACT) {
                            if (!%match) {
                                $matchnext{$seq} = (
                                    length($match) * SCORE_ALL / $wordcount + SCORE_EACH
                                ) * $vv;
                            }
                            elsif (exists $match{$seq}) {
                                $matchnext{$seq} = (
                                    length($match) * SCORE_ALL / $wordcount + SCORE_EACH
                                ) * $vv;

                                $matchnext{$seq} += $match{$seq}
                            }
                            else {
                                next;
                            }
                        }
                        elsif ($flag == MATCH_NOT and length($_[0]) == 2) {
                            delete $matchnext{$seq} if (%match);
                        }
                        else {
                            $match{$seq} += (
                                length($match) * SCORE_ALL / $wordcount + SCORE_EACH
                            ) * $vv;
                        }
                    }

                    next;
                }

                foreach my $match (@matched) {
                    if ((my $mpos = index($match, $vk, 4)) > -1) {
                        $wordcount += ord(substr($match, $mpos + 2, 1));
                    }
                }

                foreach my $match (@matched) {
                    if ((my $mpos = index($match, $vk, 4)) > -1) {
                        if ($flag == MATCH_EXACT) {
                            my $seq = substr($match, 0, 4);

                            if (!%match) {
                                $matchnext{$seq} = (
                                    (ord(substr($match, $mpos + 2, 1)))
                                    * SCORE_ALL / $wordcount + SCORE_EACH
                                ) * $vv;
                            }
                            elsif (exists $match{$seq}) {
                                $matchnext{$seq} = (
                                    (ord(substr($match, $mpos + 2, 1)))
                                    * SCORE_ALL / $wordcount + SCORE_EACH
                                ) * $vv;

                                $matchnext{$seq} += $match{$seq};
                            }
                            else {
                                next;
                            }
                        }
                        elsif ($flag == MATCH_NOT) {
                            if (%match) {
                                my $seq = substr($match, 0, 4);
                                delete $match{$seq} if exists $match{$seq};
                            }
                        }
                        else {
                            $match{substr($match, 0, 4)} += (
                                (ord(substr($match, $mpos + 2, 1)))
                                * SCORE_ALL / $wordcount + SCORE_EACH
                            ) * $vv;
                        }
                    }
                    elsif ($flag == MATCH_PART) {
                        $match{substr($match, 0, 4)} += (SCORE_PART) / $words;
                    }
                }
            }
        }

        if ($flag == MATCH_EXACT) {
            %match = %matchnext;
            $done++ unless %matchnext; # XXX
            %matchnext = ();
        }
    });

    if ($words > 1) {
        foreach my $key (keys(%match)) {
            $match{$key} /= $words;
        }
    }

    return wantarray ? %match : \%match;
}

# ----------------------
# Subroutine sync($self)
# ----------------------
sub sync {
    my $self = shift;

    foreach my $num ($self->{submin}..$self->{submax}) {
        $self->{subobj}[$num]->sync();
    }

    return $self->{obj}->sync() if $self->{obj};
}

# ------------------------------------------
# Subroutine setvar($self, $varname, $value)
# ------------------------------------------
sub setvar {
    my $self = shift;

    die "Cannot modify a read-only database"
        if $self->{flag} == O_RDONLY;

    return $self->_store("-$_[0]", $_[1]);
}

# ----------------------------------
# Subroutine getvar($self, $varname)
# ----------------------------------
sub getvar {
    my $self = shift;

    return $self->{db}{"-$_[0]"};
}

# ----------------------------------------------
# Subroutine getvars($self, $partial, $wanthash)
# ----------------------------------------------
sub getvars {
    my ($self, $partial, $flag) = @_;
    my ($value, $status, @keys);
    my $key = "-$partial";

    for ($status = $self->{obj}->seq($key, $value, R_CURSOR);
         $status == 0 and substr($key, 0, length($partial) + 1) eq "-$partial";
         $status = $self->{obj}->seq($key, $value, R_NEXT)) {
        push @keys, substr($key, 1);
        push @keys, $value if $flag;
    }

    return @keys;
}

# ------------------------------
# Subroutine getkey($self, $seq)
# ------------------------------
sub getkey {
    my $self = shift;

    return $self->{db}{"!$_[0]"};
}

# -------------------------------
# Subroutine findkey($self, $key)
# -------------------------------
sub findkey {
    my ($self, $key) = @_;
    my ($v, $status) = '!';
    my $k = '!';

    for ($status = $self->{obj}->seq($k, $v, R_CURSOR);
         $status == 0 and substr($k, 0, 1) eq '!';
         $status = $self->{obj}->seq($k, $v, R_NEXT)) {
        return substr($k, 1) if $v eq $key;
    }

    return;
}

# ------------------------------
# Subroutine delete($self, $key)
# ------------------------------
sub delete {
    my ($self, $key) = @_;

    $self->delkey($self->findkey($key));
}

# ------------------------------
# Subroutine delkey($self, $key)
# ------------------------------
sub delkey {
    my $self = shift;

    delete $self->{db}{"!$_[0]"};
    $self->{db}{_deleted} .= $_[0];
    $self->{deleted}{$_[0]} = '';
}

# ------------------------------------
# Subroutine getkeys($self, $wanthash)
# ------------------------------------
sub getkeys {
    my ($self, $flag) = @_;
    my ($v, $status, @keys);
    my $k = '!';

    for ($status = $self->{obj}->seq($k, $v, R_CURSOR);
         $status == 0 and substr($k, 0, 1) eq '!';
         $status = $self->{obj}->seq($k, $v, R_NEXT)) {
        push @keys, substr($k, 1) if $flag;
        push @keys, $v;
    }

    return @keys;
}

# ------------------------------------------
# Subroutine _store($self, $varname, $value)
# ------------------------------------------
sub _store {
    my $self = shift;

    if (DB_VERSION >= 2.0) {
        my ($k, $v) = ($_[0], undef);
        my $status = $self->{obj}->seq($k, $v, R_CURSOR);

        $self->{obj}->put($_[0], $_[1], ($k eq $_[0] and $v) ?
                                          R_CURSOR : 0);
        return $v;
    }
    else {
        my $orig = $self->{db}{$_[0]};
        if (not defined $orig) {
            return ($self->{db}{$_[0]} = $_[1]);
        } elsif ($orig ne $_[1]) {
            delete $self->{db}{$_[0]};
            return ($self->{db}{$_[0]} = $_[1]);
        }
    }
}

# ---------------------
# Destructor subroutine
# ---------------------
DESTROY {
    my $self = shift;

    $self->sync() if UNIVERSAL::can($self, 'sync');

    undef $self->{obj};
    undef $self->{db};

    foreach my $num (0..$self->{subcount} - 1) {
        undef $self->{subobj}[$num];
        undef $self->{subdb}[$num];
    }
}

1;

__END__

=head1 AUTHORS

Autrijus Tang E<lt>autrijus@autrijus.org>

=head1 COPYRIGHT

Copyright 2001 by Autrijus Tang E<lt>autrijus@autrijus.org>.

All rights reserved.  You can redistribute and/or modify
this module under the same terms as Perl itself.

=cut
