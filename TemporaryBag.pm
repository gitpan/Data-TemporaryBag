package Data::TemporaryBag;

use strict;

use Fcntl;
use IO::File;
use Carp;

use overload '""' => \&value, '.=' => \&add, '=' => \&clone, fallback => 1;
use constant FILENAME => 0;
use constant STARTPOS => 1;
use constant FINGERPRINT => 2;

use vars qw/$VERSION $Threshold $TempPath %TempFiles/;

$VERSION = '0.03';

$Threshold = 10; # KB
$TempPath  = $::ENV{'TEMP'}||$::ENV{'TMP'}||'./';
%TempFiles = ();

sub new {
    my $class = shift;
    my $self;

    $$self = '';
    bless $self, ref($class)||$class;

    $self->add(@_) if @_;
    $self;
}

sub clear {
    my $self = shift;
    my $fn = $self->is_saved;

    if ($fn) {
	unlink $fn;
	delete $TempFiles{$fn};
    } else {
	$$self = '';
    }
}

sub add {
    my ($self, $data) = @_;

    $data ||= '';

    if (ref($$self)) {
	my $fh = $self->_open(O_WRONLY|O_APPEND);
	print $fh $data;
	close $fh;
	$self->_set_fingerprint;
    } else {
	$data = ($$self or '') . $data;
	if (length($data) > $Threshold * 1024) {
	    $$self = [_new_filename(), 0];
	    my $fh = $self->_open(O_CREAT|O_EXCL|O_WRONLY|O_APPEND);
	    print $fh $data;
	    close $fh;
	    $self->_set_fingerprint;
	} else {
	    $$self = $data;
	}
    }
    $self;
}

sub substr {
    my ($self, $pos, $size, $replace) = @_;
    my $len = $self->length;
   
    unless (defined $size) {
	$size = $len;
    } elsif ($size < 0) { 
	$size = $len + $size;
    }
    $pos  = $len + $pos  if $pos  < 0;

    if ($self->is_saved) {
	my $data;
	my $fh = $self->_open(O_RDONLY);

	return '' if $pos >= $len;
	seek($fh, $pos + $$self->[STARTPOS], 0);
	read($fh, $data, $size);
	close $fh;
	if (defined $replace) {
	    my $rlen = length($replace);
	    my $newlen = $len - $size + $rlen;

	    if ($rlen == $size) {
		my $fh = $self->_open(O_RDWR);
		seek($fh, $pos + $$self->[STARTPOS], 0);
		print $fh $replace;
		close $fh;
	    } elsif ($newlen < $Threshold * 800) {
		my $data1 = $self->substr(0, $pos);
		my $data2 = $self->substr($pos + $size);
		$self->clear;
		$$self = $data1.$replace.$data2;
	    } elsif ($pos == 0 and $replace eq '') {
		$$self->[STARTPOS] += $size;
	    } elsif ($pos < 1024 and $newlen < $len + $$self->[STARTPOS]) {
		my $data;
		my $fh = $self->_open(O_RDWR);
		seek($fh, $$self->[STARTPOS], 0);
		read($fh, $data, $pos);
		$$self->[STARTPOS] += $len-$newlen;
		seek($fh, $$self->[STARTPOS], 0);
		print $fh  $data, $replace;
		close $fh;
	    } elsif ($pos + $size + 1024 >= $len) {
		my $data = '';
		my $fh = $self->_open(O_RDWR);
		if ($pos + $size < $len) {
		    seek($fh, $pos + $size + $$self->[STARTPOS], 0);
		    read($fh, $data, 1024);
		}
		seek ($fh, $pos + $$self->[STARTPOS], 0);
		print $fh  $replace, $data;
		truncate($fh, $newlen + $$self->[STARTPOS]);
		close $fh;
	    } else {
		my $t = Data::TemporaryBag->new;
		my $readpos = 0;
		while ($readpos < $pos-1024) {
		    $t->add($self->substr($readpos, 1024));
		    $readpos +=1024;
		}
		$t->add($self->substr($readpos, $pos-$readpos));
		$t->add($replace);
		$readpos = $pos + $size;
		while ($readpos < $len-1024) {
		    $t->add($self->substr($readpos, 1024));
		    $readpos +=1024;
		}
		$t->add($self->substr($readpos, $len-$readpos));
		$self->clear;
		$$self = $$t;
		$$t = '';
	    }

	}
	$self->_set_fingerprint;
	return $data;
    } else {
	return defined $replace ? 
	    substr($$self, $pos, $size, $replace) :
	    substr($$self, $pos, $size);
    }
}


sub clone {
    my ($self, $stream)=@_;
    my $size = $self->Length;
    my $pos = 0;
    my $new = $self->new;

    while ($size > $pos) {
	$new->add($self->substr($pos, 1024));
	$pos += 1024;
    }
    $new;
}

sub value {
    my ($self, $stream)=@_;
    my $size = $self->length;
    my $pos = 0;
    my $data = '';

    while ($size > $pos) {
	$data .= $self->substr($pos, 1024);
	$pos += 1024;
    }
    $data;
}

sub length {
    my $self = shift;
    my $fn = $self->is_saved;

    return $fn ? ((-s $fn) - $$self->[STARTPOS]) : length($$self);
}

sub defined {
    defined $ {$_[0]};
}

sub _open {
    my ($self, $mode) = @_;
    my $fn = $$self->[FILENAME];

    croak "TemporaryBag object seems to be collapsed " if (-e $fn and !-f $fn) or $fn!~/TempBag[A-Z0-9]+$/;

    chmod 0600, $fn if -e $fn;
    my $fp_check = $self->_check_fingerprint;
    my $fh = IO::File->new($fn, $mode, 0600);
    binmode $fh;

    croak "TemporaryBag object seems to be collapsed " unless defined $fh;
    if (defined $$self->[FINGERPRINT]) {
	croak "TemporaryBag object seems to be collapsed " unless $fp_check;
    } else {
	$self->_set_fingerprint;
    }
    return $fh;
}

sub is_saved {
    my $self = shift;

    return ref($$self) ? $$self->[FILENAME] : undef;
}

sub _set_fingerprint {
    my $self = shift;

    return unless ref($$self);

    chmod 0400, $$self->[FILENAME];
    $$self->[FINGERPRINT] = -s $$self->[FILENAME];
    $$self->[FINGERPRINT] .= ':'.(-M _ or '');
}

sub _check_fingerprint {
    my $self = shift;

    return 1 unless ref($$self);

    my $fp =  -s $$self->[FILENAME];
    $fp .= ':'. (-M _ or '');
    return (defined $$self->[FINGERPRINT] and $$self->[FINGERPRINT] eq $fp);
}

sub _new_filename {
    my $fn;

    do {
	$fn = join('', map {('A'..'Z', '0'..'9')[int(rand(36))]} (0..7));
	$fn = "$TempPath/TempBag$fn";
    } while $TempFiles{$fn} or -e $fn;
    $TempFiles{$fn}++;
    $fn;
}

sub DESTROY {
    shift->clear;
}

1;
__END__

=head1 NAME

Data::TemporaryBag - Handle long size data using temporary file .

=head1 SYNOPSIS

  use Data::TemporaryBag;

  $data = Data::TemporaryBag->new;
  # add long string
  $data->add('ABC' x 1000);
  # You can use an overridden operator
  $data .= 'DEF' x 1000;
  ...
  $substr = $data->substr(2997, 6);  # ABCDEF

=head1 DESCRIPTION

I<Data::TemporaryBag> module provides a I<bag> object class handling long size 
data.  The short size data are kept on memory.  When the data size becomes 
over I<$Threshold> size, they are saved into a temporary file internally.

=head2 METHOD

=over 4

=item Data::TemporaryBag->new( [$data] )

Creates a I<bag> object.

=item $bag->clear

Clears I<$bag>.

=item $bag->add( $data )

Adds I<$data> to I<$bag>.
You can use an assignment operator '.=' instead.

=item $bag->substr( $offset, $length, $replace )

Extracts a substring out of I<$bag>.  It behaves similar to 
CORE::substr except that it can't be an lvalue.

=item $bag->clone

Creates a clone of I<$bag>.

=item $bag->value

Gets data of I<$bag> as a string.  It is possible that the string is 
extremely long.

=item $bag->length

Gets length of data.

=item $bag->defined

Returns if the data in I<$bag> are defined or not.

=item $bag->is_saved

Returns the file name if I<$bag> is saved in a temporary file.

=back

=head2 GLOBAL VARIABLES

=over 4

=item $Data::TemporaryBag::Threshold

The threshold of the data size in kilobytes whether saved into file or not.
Default is 10.

=item $Data::TemporaryBag::TempPath

The directory path where temporary files are saved.
Default is I<$ENV{TEMP} || $ENV{TMP} || './'>.

=back

=head1 COPYRIGHT

Copyright 2001 Yasuhiro Sasama (ySas), <ysas@nmt.ne.jp>

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut
