package DBIx::Enabler::ResultSet;
# ABSTRACT: Configure the results to get what you want

=head1 SYNOPSIS

	DBIx::Enabler::ResultSet->new($enabler_query, {opt => 'val'})

The companion to a DBIx::Enabler::Query.
Provides easy access to information about the query
and enables more powerful configuration of results.

=cut

use strict;
use warnings;
use Carp qw(croak carp);
use DBIx::Enabler::Util qw(order_from_sql);

=method new

	DBIx::Enabler::ResultSet->new($query, opt => 'val');

	# Can also be instantiated from a Query object:
	DBIx::Enabler::Query->new(sql => $sql)->resultset(opt => 'val');

The first argument should be a DBIx::Enabler::Query instance.

The second argument is a hash or hashref of options.
These options will be checked in the passed hash[ref] first.
If they do not exist, they will be looked for on the Query object.

	my $dbh = DBI->connect();
	$query = DBIx::Enabler::Query->new(sql => $sql, dbh => $dbh);

	# These two invocations will produce the same result:
	# The 1st call sets 'dbh' explicitly.
	# The 2nd call will find the 'dbh' attribute on $query.

	DBIx::Enabler::ResultSet->new($query, dbh => $dbh);
	DBIx::Enabler::ResultSet->new($query);

=for :list
* I<dbh>
A database handle (the return of C<< DBI->connect() >>)
* I<drop_columns>
An arrayref of column names to be dropped (ignored) from the result set
* I<key_columns>
An arrayref of column names that define 'unique' records;
This is used by the L</hash>() method.  See also L<DBI/fetchall_hashref>.
* I<order>
An arrayref of column names to specify the sort order of the query;
If not provided this will be guessed from the SQL statement.

=cut

sub new {
	my $class = shift;
	my $query = shift;
	my %opts = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;
	my $self = {
		query => $query,
	};

	bless $self, $class;

	foreach my $var ( $self->_pass_through_args() ){
		# allow options to be specified directly
		if( exists($opts{$var}) ){
			$self->{$var} = $opts{$var};
		}
		# or look for them on the query object
		elsif( exists($self->{query}{$var}) ){
			$self->{$var} = $self->{query}{$var};
		}
	}

	# the columns attributes should be arrayrefs
	foreach my $cols ( qw(key_columns drop_columns order) ){
		if( $self->{$cols} ){
			$self->{$cols} = [$self->{$cols}]
				unless ref($self->{$cols}) eq 'ARRAY';
		}
		else{
			$self->{$cols} = [];
		}
	}

	$self->{hash_key_name} ||=
		($self->{dbh} && $self->{dbh}{FetchHashKeyName})
		|| 'NAME_lc';

	return $self;
}

=method array

	$resultset->array();   # array of arrays
	$resultset->array({}); # array of hashrefs

Calls L<fetchall_arrayref|DBI/fetchall_arrayref>(@_)
on the DBI statement handle (passing any supplied arguments).

=cut

sub array {
	my ($self) = shift;
	$self->execute() if !$self->{executed};
	$self->{sth}->fetchall_arrayref(@_);
}

=method columns

Return the columns of the recordset.

This includes key and non-key columns
and excludes dropped columns.

This is only useful after the query has been executed.

=cut

sub columns {
	my ($self) = @_;
	croak('Columns not known until after the statement has executed')
		unless $self->{executed};
	return (@{$self}{qw(key_columns non_key_columns)});
}

=method execute

Execute the I<query> against the I<dbh>.

=cut

sub execute {
	my ($self, @params) = @_;

	my $sql = $self->{query}->sql;

	# TODO: Time the query
	$self->{sth}      = $self->{dbh}->prepare($sql)
		or croak $self->{dbh}->errstr;
	$self->{executed} = $self->{sth}->execute(@params)
		or croak $self->{sth}->errstr;
	# TODO: stop timer

	# guess primary key and column order if we don't have them
	if( my $columns = $self->{sth}->{ $self->{hash_key_name} } ){
		$self->{key_columns} ||= [ $columns->[0] ];
		# get the "other" columns (not keys, not dropped)
		$self->{non_key_columns} = [];
		# TODO: Benchmark this against /^(?:${\ join('|', key, drop) })$/o
		foreach my $column ( @$columns ){
			push(@{$self->{non_key_columns}}, $column)
				unless grep { $_ eq $column }
					(@{$self}{qw(key_columns drop_columns)});
		}
		$self->{order} ||= order_from_sql($sql);
	}

	return $self->{executed};
}

=method key_columns

Return a list of the primary key columns from the query.

=method non_key_columns

Return a list of the other columns from the query.

Excludes key columns and dropped columns.

=cut

foreach my $cols ( qw(key_columns non_key_columns) ){
	no strict 'refs';
	*$cols = sub { 
		@{$_[0]->{$cols}};
	}
}

=method hash

Returns a tree of hash refs like
L<fetchall_hashref|DBI/fetchall_hashref>.

=cut

sub hash {
	my ($self) = @_;
	$self->execute() if !$self->{executed};
	return $self->fetchall_hashref($self->{key_columns});
}

=method _pass_through_args

A list of allowed arguments to the constructor that
will pass through to the new object.

This is mostly here to allow subclasses to easily overwrite it.

=cut

sub _pass_through_args {
	qw(
		dbh
		drop_columns
		hash_key_name
		key_columns
		order
	);
}

sub DESTROY {
	my ($self) = @_;
	$self->{sth}->finish() if $self->{sth};
}

1;

=for Pod::Coverage DESTROY

=cut
