package DBIx::Enabler::Query;
# ABSTRACT: More informative and powerful queries

=head1 SYNOPSIS

	DBIx::Enabler::Query->new(sql => "SELECT * FROM table");
	DBIx::Enabler::Query->new(file => "/path/to/query.sql", variables => {});
	DBIx::Enabler::Query->new({sql => \"SELECT * FROM table", variables => {}});

An object to encapsulate a database query
and various methods to provide you with more information
and configuration of your queries.

=cut

use strict;
use warnings;

use Carp qw(carp croak);
use Data::Transform::Named::Stackable ();
use DBIx::Enabler ();
use DBIx::Enabler::ResultSet ();
use Template 2.22; # Template Toolkit

=method new

First argument is the sql template to process.

=for :list
* A string is treated as a filename,
* A scalar reference is treated as the template text.

The second argument is a hash or hashref of options:

=for :list
* I<sql>
The SQL query [template] in a string (or a reference to a string)
* I<file>
The file path of a SQL query [template] (mutually exclusive with I<sql>)
* I<dbh>
A database handle (the return of C<< DBI->connect() >>)
* I<default_slice>
The default slice of the record returned from the
L<DBIx::Enabler::ResultSet/array>() method.
* I<prefix>
A string to be prepended to the SQL before parsing the template
* I<suffix>
A string to be appended  to the SQL before parsing the template
* I<variables>
A hashref of variables made available to the template

=cut

sub new {
	my $class = shift;
	my %opts = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;

	# Params::Validate not currently warranted
	# (since it's still missing the "mutually exclusive" feature)

	# defaults
	my $self = {
		variables => {},
	};

	bless $self, $class;

	foreach my $var ( $self->_pass_through_args() ){
		$self->{$var} = $opts{$var} if exists($opts{$var});
	}

	croak(q|Cannot include both 'sql' and 'file'|)
		if exists($opts{sql}) && exists($opts{file});

	# if the string is defined that's good enough
	if( defined($opts{sql}) ){
		$self->{template} = ref($opts{sql}) ? ${$opts{sql}} : $opts{sql};
	}
	# the file path should at least be a true value
	elsif( my $f = $opts{file} ){
		$self->{template} = DBIx::Enabler::slurp_file($f);
	}
	else {
		croak(q|Must specify one of 'sql' or 'file'|);
	}

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
		suffix
		transformations
		variables
	);
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

See L<DBIx::Enabler::ResultSet/hash> and L<DBIx::Enabler::ResultSet/preference>
for more information.

=cut

sub prefer {
	my ($self) = shift;
	push(@{ $self->{preferences} ||= [] }, @_);
}

=method resultset

This is a convenience method which returns a
L<DBIx::Enabler::ResultSet> object based upon this query.

Any arguments passed will be passed to the
L<ResultSet constructor|DBIx::Enabler::ResultSet/new>.

This method is aliased as C<results()>.

=cut

sub resultset {
	my ($self) = shift;
	DBIx::Enabler::ResultSet->new($self, @_);
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

	$query->transform($name, $type, [qw(fields)], @arguments);

Add a transformation to be applied to the result data.

See L<Data::Transform::Named::Stackable/push>.

=cut

sub transform {
	my ($self, @tr) = @_;
	( $self->{transformations} ||=
		Data::Transform::Named::Stackable->new() )->push(@tr);
}

1;

=for Pod::Coverage result results
