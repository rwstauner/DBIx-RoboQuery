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
	my @pass_through_args = $self->_pass_through_args();

	foreach my $var ( @pass_through_args ){
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

A list of allowed arguments to the constructor that will be set on the object.

This is mostly here to allow subclasses to easily overwrite it.

=cut

sub _pass_through_args {
	qw(
		prefix
		suffix
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
	my $sql = $self->pre_process_sql($self->{template});
	$self->{tt}->process(\$sql, $vars, \$output)
		or die($self->{tt}->error(), "\n");
	return $output;
}

1;
