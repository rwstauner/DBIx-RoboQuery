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

The first argument should be a DBIx::Enabler::Query instance.

The second argument is a hashref of options:

=for :list
* dbh          => DBI database handle
* drop_columns => an arrayref of column names to be dropped from the result set

=cut

sub new {
	my $class = shift;
	my $self = {
		query => $_[0],
		%{$_[1]}
	};

	# defaults
	$self->{dbh} ||= $self->{query}{dbh};
	$self->{drop_columns} ||= [];
	$self->{hash_key_name} ||= $self->{dbh}{FetchHashKeyName} || 'NAME_lc';

	bless {}, $class;
}

=method arrayrefs

	$resultset->arrayrefs();
	$resultset->arrayrefs({}); # get hashrefs anyway

Calls L<fetchall_arrayref|DBI/fetchall_arrayref>(@_)
on the DBI statement handle (passing any supplied arguments).

=cut

sub arrayrefs {
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
	my $sth = $self->{dbh}->prepare($sql)      or die $self->dbh->errstr;
	$self->{executed} = $sth->execute(@params) or die $self->sth->errstr;
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

	$self->{sth} = $sth;
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

=method hashrefs

Returns a tree of hash refs like
L<fetchall_hashref|DBI/fetchall_hashref>.

=cut

sub hashrefs {
	my ($self) = @_;
	$self->execute() if !$self->{executed};
	return $self->fetchall_hashref;
}

sub DESTROY {
	my ($self) = @_;
	$self->{sth}->finish() if $self->{sth};
}

1;

=for Pod::Coverage DESTROY

=cut
