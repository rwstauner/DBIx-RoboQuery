# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;

package DBIx::RoboQuery;
# ABSTRACT: Very configurable/programmable query object

use Carp qw(carp croak);
use DBIx::RoboQuery::ResultSet ();
use DBIx::RoboQuery::Util ();
use Template 2.22; # Template Toolkit

=method new

  my $query = DBIx::RoboQuery->new(%opts); # or \%opts

Constructor;  Accepts a hash or hashref of options:

=begin :list

* C<sql>
The SQL query [template] in a string;
This can be a reference to a string in case your template [query]
is large and it makes you feel better to pass it by reference.
* C<file>
The file path of a SQL query [template] (mutually exclusive with C<sql>)
* C<dbh>
A database handle (the return of C<< DBI->connect() >>)
* C<default_slice>
The default slice of the records returned;
It is not used by the query but merely passed to the ResultSet object.
See L<DBIx::RoboQuery::ResultSet/array>.
* C<drop_columns>
An arrayref of columns to be dropped from the resultset;  See L</drop_columns>.
* C<key_columns>
An arrayref of [primary key] column names;  See L</key_columns>.
* C<order>
An arrayref of column names to specify the sort order;  See L</order>.
* C<prefix>
A string to be prepended to the SQL before parsing the template
* C<squeeze_blank_lines>
Boolean; If enabled, empty lines (or lines with only whitespace)
will be removed from the compiled template.
This can make it easier to look at sql that has a lot of template directives.
(Disabled by default.)
* C<suffix>
A string to be appended  to the SQL before parsing the template
* C<template_options>
A hashref of options that will be merged into the options to
L<< Template->new()|Template >>
You can use this to overwrite the default options, but be sure to use the
C<variables> options rather than including C<VARIABLES> in this hash
unless you don't want the default variables to be available to the template.
* C<template_private_vars>
B<Not normally needed>

This is a regexp (which defaults to C<$Template::Stash::PRIVATE>
(which defaults to C<qr/^[_.]/>)).
Any template variables that match will not be accessible in the template
(but will return undef, which will throw an error under C<STRICT> mode).
If you want to access "private" variables (including "private" hash keys)
in your templates (the main query template or any templates passed to L</prefer>)
you should set this to C<undef> to tell L<Template> not to check variable names.
* C<transformations>
An instance of L<Sub::Chain::Group>
(or a hashref (See L</prepare_transformations>.))
* C<variables>
A hashref of variables made available to the template

=end :list

=cut

sub new {
  my $class = shift;
  my %opts = @_ == 1 ? %{ $_[0] } : @_;

  # Params::Validate not currently warranted
  # (since it's still missing the "mutually exclusive" feature)

  # defaults
  my $self = {
    drop_columns => [],
    key_columns => [],
    resultset_class => "${class}::ResultSet",
    variables => {},
    template_private_vars => $Template::Stash::PRIVATE,
  };

  bless $self, $class;

  foreach my $var ( $self->_pass_through_args() ){
    $self->{$var} = $opts{$var} if exists($opts{$var});
  }

  DBIx::RoboQuery::Util::_ensure_arrayrefs($self);

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

  $self->{tt} ||= Template->new({
    ABSOLUTE => 1,
    STRICT => 1,
    VARIABLES => {
      query => $self,
      %{$self->{variables}}
    },
    %{ $self->{template_options} || {} },
  })
    or die "$class error: Template::Toolkit failed: $Template::ERROR\n";

  return $self;
}

# convenience method for subclasses

sub _arrayref_args {
  qw(
    bind_params
    drop_columns
    key_columns
    order
  );
}

=method bind

  $query->bind($value);
  $query->bind($value, \%attr);
  $query->bind($p_num, $value, \%attr);

Bind a value to a placeholder in the query.
The provided arguments are saved and eventually passed to L<DBI/bind_param>.

This can be useful for passing dynamic values
through the database driver's quoting mechanism.

For convenience a placeholder is returned
so that the method can be called in place in a query template:

  # in template:
  WHERE field = [% query.bind(value) %]

The placeholder will be the standard C<?> if the index is an integer,
or it will simply return the placeholder otherwise
which can be useful for drivers that allow named parameters:

  WHERE field = [% query.bind(':foo', value, {}) %]
  # becomes 'WHERE field = :foo'

If you don't want the placeholder added to your query
use the template's syntax to discard it.
For example, with L<Template::Toolkit>:

  [% CALL query.bind(value) %]

For convenience the placeholder (C<$p_num>) will be filled in automatically
(a simple incrementing integer starting at 1)
unless you provide all three arguments
(in which case they are passed as-is to L<DBI/bind_param>).

B<Note> that the index only auto-increments if you don't supply one
(by sending all three arguments):

  $query->bind($a);         # placeholder 1
  $query->bind($b, {});     # placeholder 2
  $query->bind(2, $c, {});  # overwrite placeholder 2
  $query->bind($d);         # placeholder 3   (a total of 3 bound parameters)
  $query->bind(4, $e, {});  # placeholder 4   (a total of 4 bound parameters)
  $query->bind($f);  # auto-inc to 4 (which will overwrite the previous item)

So don't mix the auto-increment with explicit indexes
unless you know what you are doing.

Consistency and simplicity was chosen over the complexity
added by special cases based on comparing the provided index
to the current (if any) auto-increment.

=cut

sub bind {
  my ($self, @bind) = @_;

  my $bound = $self->{bind_params} ||= [];

  # auto-increment placeholder index unless all three values were passed
  unshift @bind, ++$self->{bind_params_index}
    unless @bind == 3;

  # always push (don't set $bound->[$index]) because we're just going
  # to pass all of these to bind_param() in order
  push @$bound, \@bind;

  # convenience for putting directly into place in sql
  return $bind[0] =~ /^\d+$/ ? '?' : $bind[0];
}

=method bound_params

  my @bound = $query->bound_params;
  # returns ( [ 1, "foo" ], [ 2, "bar", { TYPE => SQL_VARCHAR } ] )

Returns a list of arrayrefs representing parameters bound to the query.
Each arrayref is structured to be flattened and passed to L<DBI/bind_param>.
Each will contain it's index (or placeholder), value,
and possibly a hashref or value to hint at the data-type.

=cut

sub bound_params {
  return @{ $_[0]->{bind_params} || [] };
}

=method bound_values

This is a wrapper around L</bound_params>
that returns only the values:

  my @bound = $query->bound_values;
  # returns ("foo", "bar")

B<Note>: Values are returned in the order they were bound.
If L</bind> is used in any way other than the default auto-increment manner
the order (or even the number) of the values may be confusing and unhelpful.
In that case you probably want to use L</bound_params>
and get the values out manually.
This behavior may be improved in the future and should not be relied upon.
(Suggestions and patches for improved behavior are welcome.)
The behavior of this method
when L</bind> is used only in the default auto-increment manner
will not change.

=cut

sub bound_values {
  return map { $_->[1] } $_[0]->bound_params;
}

=method drop_columns

  # get
  my @drop_columns = $query->drop_columns;
  # set
  $query->drop_columns(@columns_to_ignore);

Accessor for the list of columns to drop (remove) from the resultset;
This works like the L</key_columns> method.

Drop columns can be useful if you need a particular column in
the query but don't really want the column in the resultset.
Some databases are inconsistent with allowing the use of a non-selected
column in an C<ORDER BY> clause, for instance.

Drop columns can also be useful if you want to compare the value of a column
in a preference statement (see L</prefer>)
but don't want the column in the actual resultset.

It may be most useful to set this value from within the template
(see L</SYNOPSIS>).

=cut

sub drop_columns {
  my ($self) = shift;
  $self->{drop_columns} = [DBIx::RoboQuery::Util::_flatten(@_)]
    if @_;
  return @{$self->{drop_columns}};
}

=method key_columns

  # get
  my @key_columns = $query->key_columns;
  # set
  $query->key_columns('id', 'fk_id');
  # empty
  $query->key_columns([]);

Accessor for the list of [primary] key columns for the query;

Any arrayrefs provided (when setting the list) will be flattened.
This allows you to empty the list by sending an empty arrayref
(if you have a reason to do so).

L<DBIx::RoboQuery::ResultSet/hash> sends the key columns
to L<DBI/fetchall_hashref> to define I<unique> records.

It may be most useful to set this value from within the template
(see L</SYNOPSIS>).

=cut

sub key_columns {
  my ($self) = shift;
  $self->{key_columns} = [DBIx::RoboQuery::Util::_flatten(@_)]
    if @_;
  return @{$self->{key_columns}};
}

=method order

  # get
  my @order = $query->order;
  # set
  $query->order(@column_order);

Accessor for the list of the column names of the sort order of the query;

This is a getter/setter which works like L</key_columns>
with one exception:
If the value has never been set
it is initialized to the list of columns from the C<ORDER BY> clause
of the sql statement as returned from
L<DBIx::RoboQuery::Util/order_from_sql>.
If there is no C<ORDER BY> clause or the statement cannot be parsed
an empty list will be returned.

It may be most useful to set this value from within the template
(see L</SYNOPSIS>), especially if your C<ORDER BY> clause is complex.

=cut

sub order {
  my ($self) = shift;
  if( @_ ){
    $self->{order} = [DBIx::RoboQuery::Util::_flatten(@_)]
  }
  # only if not previously set (empty arrayref counts as being set)
  elsif( !$self->{order} ){
    $self->{order} = [
      DBIx::RoboQuery::Util::order_from_sql(
        $self->sql, $self)
    ]
  }
  return @{$self->{order}};
}

# convenience method: args allowed in the constructor

sub _pass_through_args {
  (
    $_[0]->_arrayref_args,
  qw(
    dbh
    default_slice
    prefix
    resultset_class
    squeeze_blank_lines
    suffix
    template_options
    transformations
    template_private_vars
    variables
  ));
}

=method prepare_transformations

This method (called from the constructor)
prepares the C<transformations> attribute
(if one was passed to the constructor).

This method provides a shortcut for convenience:
If C<transformations> is a simple hash,
it is assumed to be a hash of named subs and is passed to
L<Sub::Chain::Group/new>
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

Prepend C<prefix> and append C<suffix>.
Called from L</sql> before processing the template
with the template engine.

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
of the query object (currently L<Template::Toolkit|Template>).
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

sub _process_template {
  my ($self, $template, $vars) = @_;
  my $output = '';

  # this is a regexp for vars that are considered private (will appear undef in template)
  local $Template::Stash::PRIVATE = $self->{template_private_vars};

  $self->{tt}->process($template, $vars, \$output)
    or die($self->{tt}->error(), "\n");

  return $output;
}

=method resultset

  my $resultset = $query->resultset;

This is a convenience method which returns a
L<DBIx::RoboQuery::ResultSet> object based upon this query.

To avoid confusion it caches the result
so that multiple calls to resultset()
will return the same object (rather than creating new ones).

If you desire a new resultset
(which will create a new L<DBI> statement handle)
or you desire to pass options
different than the attributes on the query,
you can manually call L<DBIx::RoboQuery::ResultSet/new>:

  my $resultset = DBIx::ResultSet->new($query, %other_options);

B<NOTE>: The ResultSet constructor calls L</sql>
before initializing the object
so that any configuration done to the query in the template
will be passed to the object at initialization.

=cut

sub resultset {
  my ($self) = shift;
  # cache this object to avoid confusion
  return $self->{resultset} ||= do {
    # taint check
    (my $class = $self->{resultset_class}) =~ s/[^a-zA-Z0-9_:']+//g;
    # make sure it's loaded first
    eval "require $class";
    die $@ if $@;

    $class->new($self);
  }
}

=method sql

  $query->sql;
  $query->sql({extra => variable});

Process the SQL template and return the result.

This method caches the result of the processed template
to avoid unexpected side effects of calling any
configuration directives (that might be in the template) multiple times.

B<NOTE>: This method gets called (without arguments)
when a resultset is created (to ensure that the query is fully
configured before copying its attributes to the ResultSet).
If you need to pass extra template variables
(that were not passed to L</new>)
you should call this method (with those variables)
before instantiating any resultset objects.

=cut

sub sql {
  my ($self, $vars) = @_;
  my $output;

  # Cache the result to avoid duplicating function calls,
  # directives, template logic, etc.
  # Plus it shouldn't need to be run more than once.
  if( exists $self->{processed_sql} ){
    $output = $self->{processed_sql};
  }
  else {
    $vars ||= {};
    my $sql = $self->pre_process_sql($self->{template});
    $output = $self->_process_template(\$sql, $vars);

    # this is fairly naive, but for SQL would usually be fine
    $output =~ s/\n\s*\n+/\n/g
      if $self->{squeeze_blank_lines};

    $self->{processed_sql} = $output;
  }
  return $output;
}

=method transform

  $query->transform($sub, %opts);
  $query->transform($sub, fields => [qw(fld1 fld2)], args => []);

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

# shortcuts

=method tr_fields

Shortcut for calling L</transform> on fields.

  $query->tr_fields("func", "fld1", "arg1", "arg2");

Is equivalent to

  $query->transform("func", fields => "fld1", args => ["arg1", "arg2"]);

The second parameter (the fields) can be either a single string
or an array ref.

=method tr_groups

Just like L</tr_fields> but the second parameter is for groups.

=cut

sub tr_fields {
  my ($self, $name, $fields, @args) = @_;
  return $self->transform($name, fields => $fields, args => [@args]);
}

sub tr_groups {
  my ($self, $name, $groups, @args) = @_;
  return $self->transform($name, groups => $groups, args => [@args]);
}

# TODO: tr_row?  could do it named func style,
# but a template of '[% row.fld1 = 0 %]' seems more useful
# (updating the hash should work, but if not this would: '[% _save_row(row) %]')

1;

=for stopwords TODO arrayrefs

=for Pod::Coverage result results

=for test_synopsis
my $dbh; # NOTE: This SYNOPSIS is read in and tested in t/synopsis.t

=head1 SYNOPSIS

  my $template_string = <<SQL;
  [%
    CALL query.key_columns('user_id');
    CALL query.drop_columns('favorite_smell');
    CALL query.prefer('favorite_smell != "wet dog"');
    CALL query.transform('format_date', {fields => 'birthday'});
  %]
    SELECT
      name,
      user_id,
      dob as birthday,
      favorite_smell
    FROM users
    WHERE dob < [% query.bind(minimum_birthdate()) %]
  SQL

  # create query object from template
  my $query = DBIx::RoboQuery->new(
    sql => $template_string,       # (or use file => $filepath)
    dbh => $dbh,                   # handle returned from DBI->connect()
    transformations => {           # functions available for transformation
      format_date => \&arbitrary_date_format,
      trim => sub { (my $s = $_[0]) =~ s/^\s+|\s+$//g; $s },
    },
    variables => {                 # variables for use in template
      minimum_birthdate => \&arbitrary_date_function,
    }
  );

  # transformations (and other configuration) can be specified in the sql
  # template or in your code if you know you'll always want certain ones
  $query->transform('trim', group => 'non_key_columns');

  my $resultset = $query->resultset;

  $resultset->execute;
  my @non_key = $resultset->non_key_columns;
  # do something where i want to know the difference between key and non-key columns

  # get records (with transformations applied and specified columns dropped)
  my $records = $resultset->hash;            # like DBI/fetchall_hashref
  # OR: my $records = $resultset->array;     # like DBI/fetchall_arrayref

=cut


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

The following enhancements are possible:

=begin :list

=item *

The query can be built with templates
(currently L<Template::Toolkit|Template>)
which allows for perl variables and functions
to interpolate and/or generate the SQL

* The output can be transformed (using L<Sub::Chain::Group>)

* TODO: list more

=end :list

See note about L</SECURITY>.

=head1 SECURITY

B<NOTE>: B<Obviously> this module is B<not> designed to take in external user input
since the SQL queries are passed through a templating engine.

This module is intended for use in internal environments
where you are the source of the query templates.

=head1 SEE ALSO

=for :list
* L<DBIx::RoboQuery::ResultSet>
* L<DBI>
* L<Template::Toolkit|Template>

=head1 TODO

=for :list
* Allow for other templating engines (or none at all)
* Consider an option for including direction (C<ASC>/C<DESC>) in L</order>
* Write a lot more tests
* Allow binding an arrayref and returning '?,?,?'
* Accept transformations or callbacks that operate on the whole row?
* Accept bind variables in the constructor?
* Add support for L<DBIx::Connector>?
