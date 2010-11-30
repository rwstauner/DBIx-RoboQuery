package THelper;

sub no_t_ex (&@) {
	SKIP: {
		package main;
		skip("$test_mod required to test exceptions", 1);
	}
}

{
	my $test_mod = 'Test::Exceptions';
	my @subs = qw(
		throws_ok
	);
	package main;
	eval "require ${test_mod}; ${test_mod}->import(); 1";
	if( $@ ){
		no strict 'refs';
		*$_ = *THelper::no_t_ex for @subs;
	}
}

1;
