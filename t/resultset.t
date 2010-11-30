use strict;
use warnings;
use Test::More;
use Test::MockObject;

my $qmod = 'DBIx::Enabler::Query';

require_ok($qmod);
my $query = $qmod->new(sql => "SELECT * FROM table1");
isa_ok($query, $qmod);

my $rmod = 'DBIx::Enabler::ResultSet';
require_ok($rmod);

my @non_keys = qw(goo ber bar baz beft blou lou);
my @columns = (qw(foo boo), @non_keys);

my $mock_sth = Test::MockObject->new({NAME_lc => [@columns]})->set_true('execute')->set_true('finish');
my $mock_dbh = Test::MockObject->new();
$mock_dbh->mock('prepare', sub { $mock_sth });

my $opts = {
	dbh => $mock_dbh,
	key_columns => 'foo',
	drop_columns => 'boo'
};

my $r = $rmod->new($query, $opts);
isa_ok($r, $rmod);

foreach my $colattr ( qw(key_columns drop_columns order) ){
	isa_ok($r->{$colattr}, 'ARRAY', "$colattr column attribute array ref");
	is_deeply($r->{$colattr}, [$opts->{$colattr} || ()], "$colattr column attribute value");
	is_deeply([$r->$colattr], [$opts->{$colattr} || ()], "$colattr method is a list");
}
is_deeply([$r->key_columns], [$opts->{key_columns}], 'key_columns is a list');

is($r->execute(), 1, 'r->execute()');
is_deeply([$r->non_key_columns], \@non_keys, 'non key columns w/o key, drop');

$mock_sth->{NAME_lc} = [qw(foo boo lou)];
is($r->execute(), 1, 'r->execute()');
is_deeply([$r->non_key_columns], [qw(lou)], 'non key columns w/o key, drop');

$r->{key_columns} = [qw(foo lou)];
is($r->execute(), 1, 'r->execute()');
is_deeply([$r->non_key_columns], [], 'non key columns w/o key, drop');

$mock_sth->{NAME_lc} = [qw(foo boo)];
is($r->execute(), 1, 'r->execute()');
is_deeply([$r->non_key_columns], [], 'non key columns w/o key, drop');

# change things up

$opts->{key_columns} = [qw(foo lou)];
$r = $rmod->new($query, $opts);
isa_ok($r, $rmod);
$mock_sth->{NAME_lc} = [qw(foo lou goo ber boo)];

my %data = (
	foo1lou1a => {foo => 'foo1', lou => 'lou1', goo => 'goo1', ber => 'ber1', boo => 'boo1'},
	foo2lou2  => {foo => 'foo2', lou => 'lou2', goo => 'goo2', ber => 'ber2', boo => 'boo2'},
	foo1lou2  => {foo => 'foo1', lou => 'lou2', goo => 'goo3', ber => 'ber3', boo => 'boo3'},
	foo2lou1  => {foo => 'foo2', lou => 'lou1', goo => 'goo4', ber => 'ber4', boo => 'boo4'},
	foo1lou1b => {foo => 'foo1', lou => 'lou1', goo => 'goo5', ber => 'ber5', boo => 'boo5'},
	foo1lou1c => {foo => 'foo1', lou => 'lou1', goo => 'goo6', ber => 'ber6', boo => 'boo6'},
);
my @data = @data{qw(foo1lou1a foo2lou2 foo1lou2 foo2lou1 foo1lou1b foo1lou1c)};

sub after_drop { my %r = %{$_[0]}; delete @r{ $opts->{drop_columns} }; \%r; }

my $exp = {
	foo1 => {
		lou2 => after_drop($data{foo1lou2})
	},
	foo2 => {
		lou2 => after_drop($data{foo2lou2}),
		lou1 => after_drop($data{foo2lou1}),
	}
};

my $reversed = 0;
sub fetchall {
	my ($root, $sth, $keys) = ({}, @_);
	for my $row ( ordered_data() ){
		my $h = $root;
		$h = ($h->{ $row->{$_} } ||= {}) for @$keys;
		@$h{keys %$row} = values %$row;
		delete @$h{ $opts->{drop_columns} };
	}
	$root;
};
sub ordered_data { $reversed ? reverse @data : @data }
sub set_data { $reversed = $_[0]; $mock_sth->set_series('fetchrow_hashref', ordered_data); }

$mock_sth->mock('fetchall_hashref', \&fetchall);

set_data(0);
$exp->{foo1}{lou1} = after_drop($data{foo1lou1c});

is_deeply($r->hash, $exp, 'hash returned expected w/ no preference');

set_data(1);
$exp->{foo1}{lou1} = after_drop($data{foo1lou1a});

is_deeply($r->hash, $exp, 'hash returned expected w/ no preference');

# now add preference
$r->{preferences} = [q[ber == 'ber4'], q[boo == 'boo5']];

set_data(1);
$exp->{foo1}{lou1} = after_drop($data{foo1lou1b});

is_deeply($r->hash, $exp, 'hash returned expected w/    preference');

# change order, expect the same
set_data(0);

is_deeply($r->hash, $exp, 'hash returned expected w/    preference');

done_testing;
