package DBIx::RoboQuery;
# ABSTRACT: Very configurable/programmable query object

=head1 SYNOPSIS

	my $template_string = <<SQL;
	[%
		query.key_columns = ['user_id']
		query.transform('format_date', {fields => 'birthday'});
	%]
		SELECT user_id,
			name,
			dob as birthday,
		FROM users
		WHERE dob < '[% minimum_birthdate() %]'
	SQL

	# create query object from template
	my $query = DBIx::RoboQuery->new(
		sql => $template_string,       # (or use file => $filepath)
		dbh => $dbh,                   # handle returned from DBI->connect()
		transformations => {           # functions available for transformation
			format_date => \&aribtrary_date_format
		}
		variables => {                 # variables for use in template
			minimum_birthdate => \&arbitrary_date_function
		}
	);

	# transformations (and other configuration) can be specified in the sql
	# template or in your code if you know you'll always want certain ones
	$query->transform('trim', group => 'non_key_columns');

	my $resultset = $query->resultset;

	# get records (with transformations applied)
	my $records = $resultset->hash; # like DBI/fetchall_hashref
	# or
	my $records = $resultset->array; # like DBI/fetchall_arrayref

=cut

use strict;
use warnings;

use Carp qw(carp croak);
use DBIx::RoboQuery::ResultSet ();
use DBIx::RoboQuery::Util ();
use Template 2.22; # Template Toolkit

=method new

First argument is the sql template to process.

=for :list
* A string is treated as a filename,
* A scalar reference is treated as the template text.

The second argument is a hash or hashref of options:

=for :list
* C<sql>
The SQL query [template] in a string;
This can be a reference to a string in case your template [query]
is large and it makes you feel better to pass it by reference.
* C<file>
The file path of a SQL query [template] (mutually exclusive with C<sql>)
* C<dbh>
A database handle (the return of C<< DBI->connect() >>)
* C<default_slice>
The default slice of the record returned from
L<DBIx::RoboQuery::ResultSet/array>.
* C<order>
An arrayref of column names to specify the sort order of the query;
If not provided this will be guessed from the SQL statement.
* C<prefix>
A string to be prepended to the SQL before parsing the template
* C<suffix>
A string to be appended  to the SQL before parsing the template
* C<transformations>
An instance of L<Sub::Chain::Group>
(or a hashref (see L</prepare_transformations>))
* C<variables>
A hashref of variables made available to the template

=cut

sub new {
	my $class = shift;
	my %opts = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;

	# Params::Validate not currently warranted
	# (since it's still missing the "mutually exclusive" feature)

	# defaults
	my $self = {
		resultset_class => "${class}::ResultSet",
		variables => {},
	};

	bless $self, $class;

	foreach my $var ( $self->_pass_through_args() ){
		$self->{$var} = $opts{$var} if exists($opts{$var});
	}

	DBIx::RoboQuery::Util::_ensure_arrayrefs($self,
		qw(order)
	);

	croak(q|Cannot include both 'sql' and 'file'|)
		if exists($opts{sql}) && exists($opts{file});

	# if the string is defined that's good enough
	if( defined($opts{sql}) ){
		$self->{template} = ref($opts{sql}) ? ${$opts{sql}} : $opts{sql};
	}
	# the file path should at least be a true value
	elsif( my $f = $opts{file} ){
		open(my $fh, '<', $f)
			or croak("Failed to open '$f': $!");
		$self->{template} = do { local $/; <$fh>; };
	}
	else {
		croak(q|Must specify one of 'sql' or 'file'|);
	}

	$self->prepare_transformations();

	$self->{tt} = Template->new(
		ABSOLUTE => 1,
		STRICT => 1,
		VARIABLES => {
			query => $self,
			%{$self->{variables}}
		}
	)
		or die "Query error: Template::Toolkit failed: $Template::ERROR\n";

	return $self;
}

=method order

Return a list of the column names of the sort order of the query.

=cut

sub order {
	my ($self) = @_;
	$self->{order} = [
		DBIx::RoboQuery::Util::order_from_sql(
			$self->{query}->sql, $self->{query})
	]
		if !@{$self->{order}};
	return @{$self->{order}};
}

=method _pass_through_args

A list of allowed arguments to the constructor that
will pass through to the new object.

This is mostly here to allow subclasses to easily overwrite it.

=cut

sub _pass_through_args {
	qw(
		dbh
		default_slice
		prefix
		resultset_class
		suffix
		transformations
		variables
	);
}

=method prepare_transformations

This method (called from the constructor)
prepares the C<transformations> attribute
(if one was passed to the constructor).

This method provides a shortcut for convenience:
If C<transformations> is a simple hash,
it is assumed to be a hash of named subs and is passed to
L<< Sub::Chain::Group->new() | Sub::Chain::Group/new >>
as the C<subs> key of the C<chain_args> hashref.
See L<Sub::Chain::Group> and L<Sub::Chain::Named>
for more information about these.

If you pass your own instance of L<Sub::Chain::Group>
this method will do nothing.
It is mostly here to help a subclass use a different module
for transformations if desired.

=cut

sub prepare_transformations {
	my ($self) = @_;

	return
		unless my $tr = $self->{transformations};

	# assume a simple hash is a hash of named subs
	if( ref $tr eq 'HASH' ){
		require Sub::Chain::Group;
		$self->{transformations} =
			Sub::Chain::Group->new(
				chain_class => 'Sub::Chain::Named',
				chain_args  => {subs => $tr},
			);
	}
	# return nothing
	return;
}

=method pre_process_sql

Prepend I<prefix> and append I<suffix>.

=cut

sub pre_process_sql {
	my ($self, $sql) = @_;
	$sql = $self->{prefix} . $sql if defined $self->{prefix};
	$sql = $sql . $self->{suffix} if defined $self->{suffix};
	return $sql;
}

=method prefer

	$query->prefer("color == 'red'", "color == 'green'");
	$query->prefer("smell == 'good'");

Accepts one or more rules to determine which record to choose
if you use C<< resultset->hash() >> and multiple records are found
for any given key field(s).

The "rules" are strings that will be processed by the templating engine
of the Query object (currently L<Template::Toolkit|Template>).
The record's fields will be available as variables.

Each rule will be tested with each record and the first one to match
will be returned.

So considering the above example,
the following code will return the second record since it will match
one of the rules first.

	$resultset->preference(
		{color => 'blue',  smell => 'good'},
		{color => 'green', smell => 'bad'}
	);

The rules are tested in the order they are set,
and the records are processed in reverse order
(to be compatible with the "last one in wins" logic of L<DBI/fetchall_hashref>).

See
L<DBIx::RoboQuery::ResultSet/hash> and
L<DBIx::RoboQuery::ResultSet/preference>
for more information.

=cut

sub prefer {
	my ($self) = shift;
	push(@{ $self->{preferences} ||= [] }, @_);
}

=method resultset

This is a convenience method which returns a
L<DBIx::RoboQuery::ResultSet> object based upon this query.

Any arguments passed will be passed to the
L<ResultSet constructor|DBIx::RoboQuery::ResultSet/new>.

This method is aliased as C<results()>.

=cut

sub resultset {
	my ($self) = shift;
	# Process the template in case it changes anything (like query.key_columns)
	# so that everything will get passed to the ResultSet.
	$self->sql();
	# TODO: cache this?
	$self->{resultset_class}->new($self, @_);
}
{
	no warnings 'once';
	*result = *results = *resultset;
}

=method sql

	$query->sql;
	$query->sql({extra => variable});

Process the SQL template and return the result.

=cut

sub sql {
	my ($self, $vars) = @_;
	$vars ||= {};
	my $output;

	# Cache the result to avoid duplicating function calls,
	# directives, template logic, etc.
	# Plus it shouldn't need to be run more than once.
	if( exists $self->{processed_sql} ){
		$output = $self->{processed_sql};
	}
	else {
		my $sql = $self->pre_process_sql($self->{template});
		$self->{tt}->process(\$sql, $vars, \$output)
			or die($self->{tt}->error(), "\n");
		$self->{processed_sql} = $output;
	}
	return $output;
}

=method transform

	$query->transform($sub, $type, [qw(fields)], @arguments);

Add a transformation to be applied to the result data.

The default implementation simply passes the arguments
to L<Sub::Chain::Group/append>.

=cut

sub transform {
	my ($self, @tr) = @_;

	croak("Cannot transform without 'transformations'")
		unless my $tr = $self->{transformations};

	$tr->append(@tr);
}

1;

=for Pod::Coverage result results

=head1 DESCRIPTION

This robotic query object can be configured to help you
get exactly the result set that you want.

It was designed to run in a completely automated (unmanned) environment and
read in a template that both builds the desired SQL query dynamically
and configures the query output.
It should be usable anywhere you desire
a highly configurable query and result set.

It (and its companion L<ResultSet|DBIx::RoboQuery::ResultSet>)
provide various methods for configuring/declaring
what to expect and what to return.
It aims to be as informative as you might need it to be.

See note about L</SECURITY>.

=head1 SECURITY

B<NOTE>: This module is B<not> designed to take in external user input
since the SQL queries are passed through a templating engine.
This module is intended for use in internal environments
where you are the source of the query templates.
