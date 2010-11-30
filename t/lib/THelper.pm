use strict;
use warnings;
package THelper;

our $ExModule = 'Test::Exceptions';

sub no_ex_module (&@) {
	SKIP: {
		package main;
		skip("$THelper::ExModule required to test exceptions", 1);
	}
}

{
	my @subs = qw(
		throws_ok
	);
	package main;
	eval "require $THelper::ExModule; $THelper::ExModule->import(); 1";
	if( $@ ){
		no strict 'refs';
		*$_ = *THelper::no_ex_module for @subs;
	}
}

1;
