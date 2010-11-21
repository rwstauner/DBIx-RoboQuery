package DBIx::Enabler::Util;
# ABSTRACT: Utility functions for DBI related tasks

=head1 SYNOPSIS

	use DBIx::Enabler::Util qw(functions);

A collection of utility functions for working with SQL and DBI.

Exports nothing by default.

=cut

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
	order_from_sql
);

=func order_from_sql

	$arrayref = order_from_sql("SELECT * FROM table ORDER BY field", {});

	$arrayref = order_from_sql(
		"SELECT * FROM table ORDER BY field FETCH 2 ROWS",
		{suffix => 'FETCH 2 ROWS'}
	);

Return an array ref of the column names of the sort order
based on the ORDER clause of a SQL statement.

Options can be specified in a hashref:

=for :list
* suffix => A string of sql that follows the ORDER BY clause;
Often ORDER BY is the last clause of the statement.
To anchor the regular expression used to find the ORDER BY clause
to the end of the string,
specify a string or regexp that follows the ORDER BY clause
and completes the statement.

=cut

sub order_from_sql {
	my ($sql, $opts) = @_;
	$opts ||= {};
	$opts->{suffix} ||= '';

	# return array ref (even if empty)
	my $order = [];

	$sql =~ /ORDER\s+BY\s+(          # start capture
		(?:\w+)                      # first column
			(?:\s*,\s*               # comma, possibly spaced
				(?:\w+)              # next column
			)*                       # repeat
		)\s*                         # end capture
		(?:$opts->{suffix})?         # possible query suffix
		\s*;?\s*$/isx                # end of SQL
	and
		$order = [split(/\s*,\s*/, $1)];

	return $order;
}

1;
