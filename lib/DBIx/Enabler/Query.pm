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
* I<variables>
A hashref of variables made available to the template

=cut

my @pass_through_args = qw(
	variables
);

sub new {
	my $class = shift;
	my %opts = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;

	# Params::Validate not currently warranted
	# (since it's still missing the "mutually exclusive" feature)

	# defaults
	my $self = {
		variables => {},
	};

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

	bless $self, $class;
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
	$self->{tt}->process(\$self->{template}, $vars, \$output)
		or die($self->{tt}->error(), "\n");
	return $output;
}

1;
