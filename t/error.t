use Test::More tests => 2;

use strict;
use warnings;

use_ok( 'HTTP::OAI' );

my $expected = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd"><responseDate>0000-00-00T00:00:00Z</responseDate><request>http://localhost/path/script?</request><error code="badVerb">You didn't supply a verb argument</error></OAI-PMH>
EOF

my $r = HTTP::OAI::Response->new(
	requestURL=>'http://localhost/path/script?',
	responseDate=>'0000-00-00T00:00:00Z',
);
$r->errors(HTTP::OAI::Error->new(code=>'badVerb',message=>'You didn\'t supply a verb argument'));

ok($r->toDOM->toString eq $expected, '<error> badVerb');
