print "1..1\n";

use strict;
use HTTP::OAI;

my $r = new HTTP::OAI::Identify(
	-baseURL=>'http://citebase.eprints.org/cgi-bin/oai2',
	-adminEmail=>'tdb01r@ecs.soton.ac.uk',
	-repositoryName=>'oai:citebase.eprints.org',
	-granularity=>'YYYY-MM-DD',
	-deletedRecord=>'transient',
);

print "ok 1\n";
