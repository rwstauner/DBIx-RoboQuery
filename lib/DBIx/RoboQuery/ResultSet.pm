package DBIx::RoboQuery::ResultSet;
# ABSTRACT: Configure the results to get what you want

=head1 SYNOPSIS

	my $resultset = DBIx::RoboQuery::ResultSet->new($query, {opt => 'val'})
	# or use $query->resultset

	$resultset->execute;
	my @columns = $resultset->columns;

	my $records = $resultset->hash; # like DBI/fetchall_hashref
	# or $resultset->array          # like DBI/fetchall_arrayref

This is the companion to L<DBIx::RoboQuery>.
Most things about the ResultSet can be configured on the query.
The ResultSet provides easy access to information about the query and results.

See L<DBIx::RoboQuery/SYNOPSIS> for a more thorough example.

=cut

use strict;
use warnings;
use Carp qw(croak carp);

=method new

	DBIx::RoboQuery::ResultSet->new($query, opt => 'val');

	# Can also be instantiated from a query object:
	DBIx::RoboQuery->new(sql => $sql)->resultset(opt => 'val');

The first argument should be a L<DBIx::RoboQuery> instance.

The remaining arguments should be a hash or hashref of options.
These options will be checked in the passed hash[ref] first.
If they do not exist, they will be looked for on the query object.

	my $dbh = DBI->connect();
	$query = DBIx::RoboQuery->new(sql => $sql, dbh => $dbh);

	# These two invocations will produce the same result:
	# The 1st call sets 'dbh' explicitly.
	# The 2nd call will find the 'dbh' attribute on $query.

	DBIx::RoboQuery::ResultSet->new($query, dbh => $dbh);
	DBIx::RoboQuery::ResultSet->new($query);

See L<DBIx::RoboQuery/new> for the list of options.

B<NOTE>: The constructor will call C<< $query->sql() >>
(and cache the result) to ensure that the query is fully
configured before copying some of its attributes
to the new resultset object.

=cut

sub new {
	my $class = shift;
	my $query = shift;
	my %opts = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;
	my $self = {
		query => $query,
		default_slice => {},

		# Process the template in case it changes anything (like query.key_columns)
		# so that everything will get passed to the ResultSet.
		sql => $query->sql(),
	};

	bless $self, $class;

	foreach my $var ( $self->_pass_through_args() ){
		# allow options to be specified directly
		if( exists($opts{$var}) ){
			$self->{$var} = $opts{$var};
		}
		# or look for them on the query object
		elsif( exists($query->{$var}) ){
			$self->{$var} = $query->{$var};
		}
	}

	DBIx::RoboQuery::Util::_ensure_arrayrefs($self);

	$self->{hash_key_name} ||=
		($self->{dbh} && $self->{dbh}{FetchHashKeyName})
		|| 'NAME_lc';

	return $self;
}

=method array

	my $array_of_hashes = $resultset->array;
	# or an array of arrays if 'default_slice' is set to an arrayref

Calls L<fetchall_arrayref|DBI/fetchall_arrayref>(@_)
on the DBI statement handle (passing any supplied arguments).

Like C<fetchall_arrayref>,
this method will take a slice as the first argument.

B< * NOTE * > :
B<Unlike> C<fetchall_arrayref>,
B<< With no arguments, or if the first argument is undefined, >>
B<< the method will act as if passed an empty hash ref. >>

To send the maximum number of desired rows it must be passed
as the second argument.

	$resultset->array();        # default is an array of hashrefs
	$resultset->array({});      # same as above
	$resultset->array([]);      # array of arrays
	$resultset->array([0]);     # array of arrays with only first column
	$resultset->array({k=>1});  # array of hashes with only column 'k'

	$resultset->array({}, 5);   # array of hashrefs,  no more than 5
	$resultset->array([], 5);   # array of arrayrefs, no more than 5

B< To Reiterate >:
This method takes the same two possible arguments as
L<DBI/fetchall_arrayref>.
B<However>, if no arguments are supplied, an empty C<{}> will be sent
to C<fetchall_arrayref> to make it return an array of hash refs.

If this deviation is undesired,
you can set C<default_slice> to C<[]> to return to the DBI default.
Like many options this can be set on the query or the resultset.

	DBIx::RoboQuery->new(default_slice => [], %opts);

=cut

sub array {
	my ($self, @args) = @_;

	# default to an array of hashrefs if no arguments are given
	@args = $self->{default_slice}
		unless @args;

	$self->execute() if !$self->{executed};

	croak('Columns unknown.  Was this a SELECT?')
		unless $self->{all_columns};

	my @tr_args = ();
	if( @args ){
		# if the slice is empty, fill it with the non-drop_columns
		my $slice = $args[0];
		if( ref($slice) eq 'HASH' and !keys(%$slice) ){
			$slice->{$_} = 1 for $self->columns;
		}
		elsif( ref($slice) eq 'ARRAY' and !@$slice ){
			my @col  = @{$self->{all_columns}};
			my %drop = map { $_ => 1 } @{ $self->{drop_columns} };
			push(@$slice, grep { !$drop{ $col[$_] } } 0 .. $#col);
			# set the first (only) element to an arrayref of column names
			@tr_args = ( [@col[@$slice]] );
		}
	}
	my $rows = $self->{sth}->fetchall_arrayref(@args);
	# if @tr_args is empty, the hash will be the only argument sent
	return $self->{transformations}
		? [map { $self->{transformations}->call(@tr_args, $_) } @$rows]
		: $rows;
}

# convenience method for subclasses

sub _arrayref_args {
	my ($self) = @_;
	return $self->{query}->_arrayref_args;
}

=method columns

	my @columns = $resultset->columns;

Return the columns of the result set.

This includes key and non-key columns
and excludes dropped columns.

This is only useful after the query has been executed
(and will C<croak> if it has not been).

=cut

sub columns {
	my ($self) = @_;
	croak('Columns not known until after the statement has executed')
		unless $self->{executed};
	return map { @{$self->{$_}} } qw(key_columns non_key_columns);
}

=method drop_columns

	my @columns = $resultset->drop_columns;

Return a list of the column names being dropped
(ignored) from the result set.

=cut

sub drop_columns {
	return @{$_[0]->{drop_columns}};
}

=method execute

	$resultset->execute();

Execute the C<query> against the C<dbh>.

=cut

sub execute {
	my ($self, @params) = @_;

	# the sql attribute is cached from $query->sql in the constructor
	my $sql = $self->{sql};

	# TODO: Time the query
	$self->{sth}      = $self->{dbh}->prepare($sql)
		or croak $self->{dbh}->errstr;
	$self->{executed} = $self->{sth}->execute(@params)
		or croak $self->{sth}->errstr;
	# TODO: stop timer

	if( my $columns = $self->{sth}->{ $self->{hash_key_name} } ){
		# save the full order for later (but break the reference)
		$self->{all_columns} = [@$columns];
		# get the "other" columns (not keys, not dropped)
		my %other = map { $_ => 1 }
			map { @{$self->{$_}} } qw(key_columns drop_columns);
		$self->{non_key_columns} = [ grep { !$other{$_} } @$columns ];

		if( my $transformations = $self->{transformations} ){
			foreach my $groups (
				[key => $self->{key_columns}],
				[non_key => $self->{non_key_columns}],
				# aliases
				[key_columns => {in => 'key'}],
				[non_key_columns => {in => 'non_key'}],
			){
				$transformations->group(@$groups);
			}
			# set all the columns so we can use group exclusions
			$transformations->fields(@$columns);
		}
	}

	# FIXME: check $self->{sth}->errstr (or someting: see DBI)
	# to make sure we got all records without error

	return $self->{executed};
}

=method hash

	my $hash_of_hashes = $resultset->hash;

Returns a tree of hashrefs like
L<DBI/fetchall_hashref>.

Records will be stored (and considered unique)
according to the C<key_columns> attribute.
If more than one record has the same values for C<key_columns>
the last record from the database will be returned.

The C<preferences> attribute can be used to determine which record
to select instead of simply the last one received.
See L</preference> for more information,
or L<DBIx::RoboQuery/prefer>
for how to write and store the preference rules.

An error is thrown if C<key_columns> is empty.
L<DBI/fetchall_hashref> doesn't check the length of C<key_columns>.
An empty array ends up returning a single hash (the last row)
instead of the hash tree which can be very confusing
and surely is not desired.
There are more efficient ways to get the last row
if that's really all you want.

=cut

sub hash {
	my ($self) = @_;
	$self->execute() if !$self->{executed};
	# TODO: care if this is called more than once?
	my $sth = $self->{sth};

	my @key_columns  = @{ $self->{key_columns}  }
		or croak('Cannot use hash() with an empty key_columns attribute');

	# We could just return $sth->fetchall_hashref(\@key_columns) if there are
	# no preferences but we can't slice out the dropped columns that way.

	my @drop_columns = @{ $self->{drop_columns} };
	my @columns = (@key_columns, @{ $self->{non_key_columns} });

	# we have to save the dropped columns so we can send them to preference()
	my ($root, $dropped) = ({}, {});

	# NOTE: It seemed to me more powerful to transform the data upon fetch
	# rather than upon storage in the tree: it gives you the option of
	# pre-transforming the keys to adjust the way the tree is built
	# and lets you know what to expect in the preference rules.
	# Plus it was easier to implement.
	# I can't think of a reason to want transform the key columns in the record
	# but not the tree (ex: {A => {B => {k1 => 'a', k2 => 'b'}}})
	# If you want un-adultered data for preferences you can select the column
	# again with an alias and then drop it.

	my $tr = $self->{transformations};
	my $fetchrow = $tr
		# don't attempt to transform if the fetch returned undef
		? sub { my $r = $sth->fetchrow_hashref(); $r && $tr->call($r); }
		: sub {         $sth->fetchrow_hashref(); };

	# check for preferences once... if there are none, do the quick version
	if( !$self->{preferences} || !@{$self->{preferences}} ){
		# we can't honor drop_columns with fetchall_hashref(), so fake it
		while( my $row = $fetchrow->() ){
			my $hash = $root;
			$hash = ($hash->{ $row->{$_} } ||= {}) for @key_columns;
			@$hash{@columns}  = @$row{@columns};
		}
	}
	else {
		while( my $row = $fetchrow->() ){
			my ($hash, $drop) = ($root, $dropped);
			# traverse hash tree to get to {key1 => {key2 => {record}}}
			foreach ( @key_columns ){
				$hash = ($hash->{ $row->{$_} } ||= {});
				$drop = ($drop->{ $row->{$_} } ||= {});
			}
			# if there's already a record there (not an empty hash)
			# (a few benchmarks suggest keys() may be faster than exists())
			if( keys %$hash ){
				$row = $self->preference({%$drop, %$hash}, $row);
			}
			@$drop{@drop_columns} = @$row{@drop_columns};
			@$hash{@columns}  = @$row{@columns};
		}
	}
	return $root;
}

=method key_columns

	my @keys = $resultset->key_columns;

Return a list of the primary key columns from the query.

The C<key_columns> attribute should be set on the query object.
This read-only accessor is provided here for convenience
and consistency with the other I<column> attributes.

=cut

sub key_columns {
	my ($self) = @_;
	return @{$self->{key_columns}};
}

=method non_key_columns

	my @other = $resultset->non_key_columns;

Return a list of the other columns from the query.

Excludes key columns and dropped columns.

=cut

sub non_key_columns {
	my ($self) = @_;
	croak('Columns not known until after the statement has executed')
		unless $self->{executed};
	# An empty array should mean that the rest are key or drop columns.
	# If not defined, there's a problem.
	croak('Columns unknown.  Was this a SELECT?')
		unless $self->{non_key_columns};
	return @{$self->{non_key_columns}};
}

# convenience method: args allowed in the constructor

sub _pass_through_args {
	(
		$_[0]->_arrayref_args,
	qw(
		dbh
		default_slice
		hash_key_name
		preferences
		transformations
	));
}

=method preference

	$resultset->preference($record1, $record2);

This is used internally by the L</hash> method to determine which record
it should choose when multiple records have the same key value(s).

When L<DBI/fetchall_hashref>
encounters multiple records having the same key field(s),
the last encountered record is the one saved to the hash and returned.

This "last one in wins" logic is preserved in this method
for any records that cannot be determined by the specified preference rules.

See L<DBIx::RoboQuery/prefer> for details on specifying record preferences.

=cut

sub preference {
	my ($self, @records) = @_;
	my $rules = $self->{preferences};

	# return last record if there are no preferences
	return $records[-1]
		if !$rules || !@$rules;

	my $templater = $self->{query}->{tt};

	foreach my $rule ( @$rules ){
		my $template = "[% IF $rule %]1[% ELSE %]0[% END %]";
		# reverse records so that if any are equal the last one in wins
		foreach my $record ( reverse @records ){
			my $found = '';
			$templater->process(\$template, $record, \$found);
			return $record if $found;
			#$self->evaluate_preference($self->{query}{tt}, $rule, $record);
		}
	}
	# last record is DBI compatibile plus it is often the newest record
	return $records[-1];
}

=method query

	my $query = $resultset->query;

Returns the query object (in case you lost it).

=cut

sub query {
	return $_[0]->{query};
}

# The DBI objects clean up after themselves, so DESTROY not currently warranted

1;

=for stopwords DBI's hashrefs
TODO

=head1 CAVEATS

While there is I<some> error checking,
the module probably assumes you're setting L<DBI/RaiseError>
to true on your C<dbh>.

If you don't use L<DBI/RaiseError>, and you experience problems,
please let me know (submit a patch or a bug report).

=head1 TODO

=for :list
* Evaluate preference for L</array> if key_columns is set?
