use Test::More tests => 3;

use strict;
use warnings;

use_ok( 'HTTP::OAI::ResumptionToken' );

my $rt = HTTP::OAI::ResumptionToken->new;
$rt->resumptionToken('');

ok(!$rt);

$rt->resumptionToken('token');

ok($rt);
