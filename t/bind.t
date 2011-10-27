# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;
use Test::More 0.96;
use Test::MockObject 1.09 ();

my $qmod = 'DBIx::RoboQuery';
eval "require $qmod" or die $@;

my $sql = 'SELECT * FROM table';
my $query = new_ok($qmod, [sql => $sql, bind_params => []]);

is($query->{bind_params_index}, undef, 'auto-increment for bind-params not started');
is_deeply($query->{bind_params}, [], 'empty bind params');

is($query->bind('foo'), '?', 'got placeholder back from bind()');
is_deeply($query->{bind_params}, [[1, 'foo']], 'arguments for bind_param');

is($query->bind(bar => { type => 'baz' }), '?', 'got placeholder');
is_deeply($query->{bind_params}, [[1, 'foo'], [2, 'bar', { type => 'baz' }]], 'arguments for bind_param');

is($query->bind(':yar' => bar => { type => 'baz' }), ':yar', 'got :named placeholder');
is_deeply($query->{bind_params}, [[1, 'foo'], [2, 'bar', { type => 'baz' }], [':yar', 'bar', { type => 'baz' }]], 'arguments for bind_param');

is($query->bind('$7' => 1 => {}), '$7', 'got $n placeholder');
is_deeply($query->{bind_params}, [[1, 'foo'], [2, 'bar', { type => 'baz' }], [':yar', 'bar', { type => 'baz' }], ['$7', 1, {}]], 'arguments for bind_param');

# TODO: bind(['hi'], ['there']) == '?,?'

{
  my $query = new_ok($qmod, [sql => $sql]);
  my ($a, $b, $c, $d, $e, $f) = qw(a b c d e f);

  # bind() calls copied from Pod
  $query->bind($a);         # placeholder 1
    is_deeply $query->{bind_params}, [[1, 'a']], 'first value bound to 1';
  $query->bind($b, {});     # placeholder 2
    is_deeply $query->{bind_params}, [[1, 'a'], [2, 'b', {}]], '2nd value';
  $query->bind(2, $c, {});  # overwrite placeholder 2
    is_deeply $query->{bind_params}, [[1, 'a'], [2, 'b', {}], [2, 'c', {}]], 'overwrite index';
  $query->bind($d);         # placeholder 3   (a total of 3 bound parameters)
    is_deeply $query->{bind_params}, [[1, 'a'], [2, 'b', {}], [2, 'c', {}], [3, 'd']], 'autoinc 3';
  $query->bind(4, $e, {});  # placeholder 4   (a total of 4 bound parameters)
    is_deeply $query->{bind_params}, [[1, 'a'], [2, 'b', {}], [2, 'c', {}], [3, 'd'], [4, 'e', {}]], 'set 4';
  $query->bind($f);  # auto-inc to 4 (which will overwrite the previous item)
    is_deeply $query->{bind_params}, [[1, 'a'], [2, 'b', {}], [2, 'c', {}], [3, 'd'], [4, 'e', {}], [4, 'f']], 'overwrite 4';

  my $r = $query->resultset;
  my $sth = Test::MockObject->new({bind => {}})
    # use hash to ensure that the right index gets the right value
    ->mock(bind_param => sub { $_[0]->{bind}->{ $_[1] } = $_[2] })
    ->mock(execute    => sub { 1 });
  $r->{dbh} = Test::MockObject->new()->mock(prepare => sub { $sth });
  $r->execute;
  is_deeply $sth->{bind}, { 1 => 'a', 2 => 'c', 3 => 'd', 4 => 'f' }, 'proper bound values';
}

done_testing;
