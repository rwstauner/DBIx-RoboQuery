package DBIx::Enabler::Query;
# ABSTRACT: More informative and powerful queries

=head1 SYNOPSIS

	DBIx::Enabler::Query->new(\"SELECT * FROM table");
	DBIx::Enabler::Query->new("/path/to/query.sql", variables => {});

An object to encapsulate a database query
and various methods to provide you with more information
and configuration of your queries.

=cut

use strict;
use warnings;

use Template 2.22; # Template Toolkit

=method new

First argument is the sql template to process.

=for :list
* A string is treated as a filename,
* A scalar reference is treated as the template text.

The I<variables> attribute can be set to a hashref
of variables made avaiable to the template.

=cut

sub new {
	my $class = shift;
	my $self = {
		variables => {},
		template => shift,
		(@_ == 1 ? %{@_} : @_)
	};

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
	$self->{tt}->process($self->{template}, $vars, \$output)
		or die($self->{tt}->error(), "\n");
	return $output;
}

1;
