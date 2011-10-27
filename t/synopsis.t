# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;
use Test::More 0.96;
use DBIx::RoboQuery;

# try to keep things a little organized... script near the top, helper subs at the bottom

# don't make these prereqs for the distribution, but we need them for this author test
my ($dbd, $pod_parser) = qw(SQLite Pod::Eventual::Simple);
foreach my $req ( 'DBI', "DBD::$dbd", $pod_parser ){
  eval "require $req";
  plan skip_all => "$req required for this test"
    if $@;
}

# all the tests are in the heredoc:
plan tests => 12;

# test everything in DBIx::RoboQuery/SYNOPSIS
my $tests = <<'TESTS';
is_deeply([$query->key_columns],  [qw(user_id)], 'key columns');
is_deeply([$query->drop_columns], [qw(favorite_smell)], 'drop columns');
# 2:
  is_deeply([$query->$_], [$resultset->$_], "query and resultset have same $_")
    for qw(key_columns drop_columns);

is_deeply( $query->{preferences}, ['favorite_smell != "wet dog"'], 'preference');
isa_ok($query->{transformations}, 'Sub::Chain::Group');
# 2:
  is_deeply([$query->{$_}], [$resultset->{$_}], "query and resultset have same $_")
    for qw(preferences transformations);

like($query->sql, qr[^\s*SELECT user_id,.+FROM users\s+WHERE dob < \?\s*$]s, 'expected SQL');
is_deeply($resultset->{bind_params}, [[1, '2000-01-01']], 'bind values');
is_deeply(\@non_key, [qw(name birthday)], 'non_key columns');
is_deeply($records, expected_records, 'expected records');
TESTS

my $dbh = prepare_database();
my $pod = get_synopsis_pod();

eval $pod . "\n" . $tests;
die $@ if $@;

done_testing;

# end test script; only subs follow:

sub prepare_database {
  my $dbh = DBI->connect("dbi:$dbd:dbname=:memory:");
  $dbh->do(q[CREATE TABLE users (user_id integer, name text, dob datetime, favorite_smell text)]);

  my @trees = (
    [1, ' Bob ', '1999-03-03 ', "\tstrawberries"],
    [2, 'Jim ', '1998-04-04', "grass\n"],
    [2, 'Tim', '1998-04-05', 'wet dog'],
    [3, 'Tim', '2002-06-06', 'cheese'],
  );
  my $sth = $dbh->prepare(q[INSERT INTO users VALUES(?, ?, ?, ?)]);
  $sth->execute(@$_) for @trees;
  return $dbh;
}

sub expected_records {
  return +{
    1 => {user_id => 1, name => 'Bob', birthday => '1999/03/03'},
    2 => {user_id => 2, name => 'Jim', birthday => '1998/04/04'},
  };
}

sub arbitrary_date_format   { (my $s = $_[0]) =~ tr|-|/|; $s }
sub arbitrary_date_function { '2000-01-01' }

# use actual SYNOPSIS
sub get_synopsis_pod {
  my $pod = '';
  my @paras = @{Pod::Eventual::Simple->read_file($INC{'DBIx/RoboQuery.pm'})};
  my $in_synopsis = 0;
  foreach my $para (@paras){
    if( $para->{type} eq 'command' ){
      #print STDERR Dumper($para);
      if( $para->{command} eq 'head1' && $para->{content} =~ /SYNOPSIS/ ){
        $in_synopsis = 1;
      }
      # the next command after =head1 SYNOPSIS ends the synopsis
      elsif( $in_synopsis && $para->{command} ){
        last;
      }
    }
    elsif( $in_synopsis ){
      $pod .= $para->{content};
    }
  }
  return $pod;
}
