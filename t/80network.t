#!/usr/bin/perl -w

use Test::More tests => 5;

use strict;
use warnings;

use HTTP::OAI;

my @repos = qw(
http://eprints.ecs.soton.ac.uk/perl/oai2
http://citebase.eprints.org/cgi-bin/oai2
http://memory.loc.gov/cgi-bin/oai2_0
);
@repos = qw(
http://eprints.ecs.soton.ac.uk/perl/oai2
);

my $h = HTTP::OAI::Harvester->new(debug=>0,baseURL=>$repos[int(rand(@repos))]);

my $r;

my $dotest = defined($ENV{"HTTP_OAI_NETTESTS"});

SKIP : {
	skip "Skipping flakey net tests (set HTTP_OAI_NETTESTS env. variable to enable)", 5 unless $dotest;

	#$r = $h->GetRecord(identifier=>'oai:eprints.ecs.soton.ac.uk:23',metadataPrefix=>'oai_dc');
	#ok($r->is_success());

	
	$r = $h->Identify();
	ok($r->is_success());

	$r = $h->ListIdentifiers(metadataPrefix=>'oai_dc');
	ok($r->is_success());

	$r = $h->ListMetadataFormats();
	ok($r->is_success());

	$r = $h->ListRecords(metadataPrefix=>'oai_dc');
	ok($r->is_success());

	$r = $h->ListSets();
warn $r->message if $r->is_error;
	ok($r->is_success());
}
