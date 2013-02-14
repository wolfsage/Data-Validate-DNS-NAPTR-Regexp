package Data::Validate::DNS::NAPTR::Regexp;

our $VERSION = '0.001';

use 5.008000;

use strict;
use warnings;

require XSLoader;
XSLoader::load('Data::Validate::DNS::NAPTR::Regexp', $VERSION);

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(is_naptr_regexp naptr_regexp_error);

our @EXPORT = @EXPORT_OK;

my $REG_EXTENDED = constant('REG_EXTENDED');
my $REG_ICASE    = constant('REG_ICASE');

my $last_error;

sub new {
	my ($class) = @_;

	return bless {}, $class;
}

sub _set_error {
	my ($where, $error) = @_;

	if ($where) {
		$where->{error} = $error;
	} else {
		$last_error = $error;
	}
}

sub error {
	my ($self) = @_;

	if ($self) {
		return $self->{error};
	} else {
		return $last_error;
	}
}

sub naptr_regexp_error {
	goto &error;
}

sub is_naptr_regexp {
	my ($self, $string) = @_;

	# Called as a function?
	if (defined $self && !ref $self) {
		$string = $self;

		$self = undef;

		$last_error = undef;
	}

	if (!defined $string) {
		return 1;
	}

	if (length $string > 255) {
		_set_error($self, "Must be less than 256 bytes");

		return 0;
	}

	if (!($string =~ s/^(.)//)) {
		return 2;
	}

	if ($string =~ /\0/) {
		_set_error($self, "Contains null bytes");

		return 0;
	}

	my $delim = $1;

	if ($delim =~ /^[0-9\\i\0]$/) {
		_set_error($self, "Delimiter ($delim) cannot be a flag, digit or null");

		return 0;
	}

	$delim = qr/\Q$delim\E/;

	# Convert double-backslashes to \0 for easy parsing.
	$string =~ s/\\\\/\0/g;

	# Now anything preceeded by a '\' is an escape sequence. If it's a 
	# digit, it must be followed by 3 digits with a total of less than 256 
	# (ASCII). If it's not a digit, we just take it for what it is.

	unless ($string =~ /^
		(.*) (?<!\\) $delim
		(.*) (?<!\\) $delim
		(.*)$/x
	) {
		_set_error($self, "Bad syntax, missing replace/end delimiter");

		return 0;
	}

	my ($find, $replace, $flags) = ($1, $2, ($3 || ''));

	# Extra delimiters? Broken
	for my $f ($find, $replace, $flags) {
		if ($f =~ /(?<!\\)$delim/) {
			_set_error($self, "Extra delimiters");

			return 0;
		}

		my @escapes = $f =~ /\\(\d{1,3})/g;

		for my $esc (@escapes) {
			if (length($esc) != 3) {
				_set_error($self, "Bad escape sequence '\\$esc'");

				return 0;
			} elsif ($esc > 255) {
				_set_error($self, "Escape sequence out of range '\\$esc'");

				return 0;
			}
		}
	}

	# Count backrefs in replace and make sure it matches up.
	# Since we're counting backrefs in the master-file format, \0 is our
	# escape character (we converted literal escapes (\\\\) above).
	# So now \0\0 is a literal '\', and \0\d is a backref. To count 
	# backrefs, we have to kill off the literals first.

	# I should switch to character parsing. It'd be more clear... -- alh
	my $temp_replace = $replace;

	$temp_replace =~ s/\0\0//g;

	my %brefs = map { $_ => 1 } $temp_replace =~ /\0([0-9])/g;

	# And so ends our fun with escapes. Convert those nulls back to double 
	# backslashes
	$_ =~ s/\0/\\\\/g for ($find, $replace, $flags);

	my $rflags = $REG_EXTENDED;

	# Validate flags
	for my $f (split //, $flags) {
		if ($f eq 'i') {
			$rflags |= $REG_ICASE;
		} else {
			_set_error($self, "Bad flag: $f");

			return 0;
		}
	}

	# Validate regex
	my ($nsub, $err) = _regcomp($find, $rflags);

	if (!defined $nsub) {
		_set_error($self, "Bad regex: $err");

		return 0;
	}

	if ($brefs{0}) {
		_set_error($self, "Bad backref '0'");

		return 0;
	}

	my ($highest) = sort {$a <=> $b} keys %brefs;
	$highest ||= 0;

	if ($nsub < $highest) {
		_set_error($self, "More backrefs in replacement than captures in match");

		return 0;
	}

	return 3;
}

1;
__END__

=head1 NAME

Data::Validate::DNS::NAPTR::Regexp - Validate the NAPTR Regexp field per RFC 2915

=head1 SYNOPSIS

Functional API (uses globals!!):

  use Data::Validate::DNS::NAPTR::Regexp;

  my $regexp = '!test(something)!\\\\1!i';

  if (is_naptr_regexp($regexp)) {
    print "Regexp '$regexp' is okay!"; 
  } else {
    print "Regexp '$regexp' is invalid: " . naptr_regexp_error();
  }

  # Output:
  # Regexp '!test(something)!\\1!i' is okay!

Object API:

  use Data::Validate::DNS::NAPTR::Regexp ();

  my $v = Data::Validate::DNS::NAPTR::Regexp->new();

  my $regexp = '!test(something)!\\\\1!i';

  if ($v->is_naptr_regexp($regexp)) {
    print "Regexp '$regexp' is okay!";
  } else {
    print "Regexp '$regexp' is invalid: " . $v->naptr_regexp_error();
  }

  # Output:
  # Regexp '!test(something)!\\1!i' is okay!

  # $v->error() also works

=head1 DESCRIPTION

This module validates the Regexp field in the NAPTR DNS Resource Record as 
defined by RFC 2915.

It assumes that the data is in master file format and suitable for use in a ISC 
BIND zone file.

=head1 EXPORT

By default, L</is_naptr_regexp> and L<naptr_regexp_error> will be exported. If 
you're using the L</OBJECT API>, importing an empty list is recommended.

=head1 FUNCTIONAL API

=head2 Methods

=head3 is_naptr_regexp

  is_naptr_regexp('some-string');

Returns a true value if the provided string is a valid Regexp for an NAPTR 
record. Returns false otherwise. To determine why a Regexp is invalid, see 
L</naptr_regexp_error> below.

=head3 naptr_regexp_error

  naptr_regexp_error();

Returns the last string error from a call to L</is_naptr_regexp> above. This is 
only valid if L</is_naptr_regexp> failed and returns a false value.

=head1 OBJECT API

This is the preferred method as the functional API uses globals.

=head2 Constructor

=head3 new

  Data::Validate::DNS::NAPTR::Regexp->new(%args)

Currently no C<%args> are available but this may change in the future.

=head3 is_naptr_regexp

  $v->is_naptr_regexp('some-string');

See L</is_naptr_regexp> above.

=head3 naptr_regexp_error

  $v->naptr_regexp_error();

See L</naptr_regexp_error> above.

=head3 error

  $v->error();

See L</naptr_regexp_error> above.

=head1 SEE ALSO

RFC 2915 - L<https://tools.ietf.org/html/rfc2915>

=head1 AUTHOR

Matthew Horsfall (alh) - <wolfsage@gmail.com>

=head1 CREDITS

The logic for this module was adapted from ISC's BIND - 
L<https://www.isc.org/software/bind>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 Dyn, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.9 or,
at your option, any later version of Perl 5 you may have available.

=cut