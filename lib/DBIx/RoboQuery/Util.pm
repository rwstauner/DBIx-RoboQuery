package DBIx::RoboQuery::Util;
# ABSTRACT: Utility functions for DBIx::RoboQuery

=head1 SYNOPSIS

	use DBIx::RoboQuery::Util ();

A collection of utility functions for L<DBIx::RoboQuery>.

=cut

use strict;
use warnings;

# convenience function used in both modules
# to convert specific hash items to arrayrefs

sub _ensure_arrayrefs {
	my ($hash, @keys) = @_;
	foreach my $key ( @keys ){
		if( $hash->{$key} ){
			$hash->{$key} = [$hash->{$key}]
				unless ref($hash->{$key}) eq 'ARRAY';
		}
		else{
			$hash->{$key} = [];
		}
	}
}

=func order_from_sql

	# returns qw(fld1)
	@order = order_from_sql("SELECT * FROM table ORDER BY field");

	# returns qw(fld1 fld2)
	@order = order_from_sql(
		"SELECT * FROM table ORDER BY fld1, fld2 FETCH 2 ROWS",
		{suffix => 'FETCH 2 ROWS'}
	);
		# suffix can also be an re: qr/FETCH \d+ ROWS/

Return a list of the column names that make up the sort order
based on the ORDER BY clause of a SQL statement.

Options can be specified in a hashref:

=for :list
* I<suffix>
A string of sql (or a regular expression compiled with qr//)
that follows the ORDER BY clause;
Often ORDER BY is the last clause of the statement.
To anchor the regular expression used to find the ORDER BY clause
to the end of the string,
specify a string or regexp that follows the ORDER BY clause
and completes the statement.

Other modules that could be used instead:

=for :list
* L<SQL::Statement>
* L<SQL::OrderBy>

=cut

sub order_from_sql {
	my ($sql, $opts) = @_;
	# TODO: consider including /|LIMIT \d+/ in suffix unless 'no_limit' provided
	$opts ||= {};

	my $suffix = $opts->{suffix}
		# don't inherit /x from the parent re below
		? qr/(?-x:$opts->{suffix})?/
		# nothing
		: qr//;

	return
	$sql =~ /\bORDER\s+BY\s+         # start order by clause
		(                            # start capture
			(?:\w+)                  # first column
			(?:\s*,\s*               # comma, possibly spaced
				(?:\w+)              # next column
			)*                       # repeat
		)\s*                         # end capture
		$suffix                      # possible query suffix
		\s*;?\s*\Z                   # end of SQL
	/isx
		? split(/\s*,\s*/, $1)
		: ();
}

1;

=head1 EXPORTS

None.
The functions in this module are not intended for public
consumption.
If you choose to ignore this and you really want to
export a subroutine, see L<Sub::Exporter>.
