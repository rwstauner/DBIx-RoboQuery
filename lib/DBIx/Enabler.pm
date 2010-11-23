package DBIx::Enabler;
# ABSTRACT: Enable yourself to do more with DBI

use strict;
use warnings;

# slurp_file is not in Util b/c it isn't DBI or SQL related
{
	local $@;
	# Don't require the user to install File::Slurp
	my $slurp = eval "require File::Slurp";
	   $slurp = 0 if $@;
	no warnings 'once';
	*slurp_file = $slurp
		? \&File::Slurp::read_file
		: sub { local (@ARGV, $/) = @_; <> };
}

1;

=for Pod::Coverage slurp_file

=head1 DESCRIPTION

Currently this module is just a namespace.

The modules in this namespace are meant to enable
the user to do more than basic DBI programming.

This means getting more information
and doing more powerful things.

=head1 SEE ALSO

=for :list
* L<DBIx::Enabler::Query>
* L<DBIx::Enabler::ResultSet>
* L<DBIx::Enabler::Util>

=cut
