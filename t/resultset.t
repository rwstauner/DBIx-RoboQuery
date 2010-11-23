use strict;
use warnings;
use Test::More tests => 22;
use Test::MockDBI;
use Test::MockObject;

my $dbh = Test::MockDBI->get_instance;
my $qmod = 'DBIx::Enabler::Query';

require_ok($qmod);
my $query = $qmod->new(sql => "SELECT * FROM table1", dbh => $dbh);
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
