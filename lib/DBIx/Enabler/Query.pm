package DBIx::Enabler::Query;

=head1 SYNOPSIS

	new DBIx::Enabler::Query(\"SELECT * FROM table");
	new DBIx::Enabler::Query("/path/to/query.sql", variables => {});

An object to encapsulate a database query
and various methods to provide you with more information
and configuration of your queries.

=cut

use strict;
use warnings;

use Template 2.22; # Template Toolkit

sub new {
	my $class = shift;
	my $self = {
		variables => {},
		template => shift,
		(@_ == 1 ? %{@_} : @_)
	};

	$self->{tt} = Template->new(
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
