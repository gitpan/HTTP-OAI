print "1..5\n";

use HTTP::OAI;

my @repos = qw(
http://eprints.ecs.soton.ac.uk/perl/oai2
http://citebase.eprints.org/cgi-bin/oai2
http://memory.loc.gov/cgi-bin/oai2_0
);

my $h = HTTP::OAI::Harvester->new(debug=>0,baseURL=>$repos[int(rand(@repos))]);

my $r;

#$r = $h->GetRecord(identifier=>'oai:eprints.ecs.soton.ac.uk:23',metadataPrefix=>'oai_dc');
#print $r->is_success() ? "ok\n" : "not ok\n";
$r = $h->Identify();
print $r->is_success() ? "ok\n" : "not ok\n";
$r = $h->ListIdentifiers(metadataPrefix=>'oai_dc');
print $r->is_success() ? "ok\n" : "not ok\n";
$r = $h->ListMetadataFormats();
print $r->is_success() ? "ok\n" : "not ok\n";
$r = $h->ListRecords(metadataPrefix=>'oai_dc');
print $r->is_success() ? "ok\n" : "not ok\n";
$r = $h->ListSets();
print $r->is_success() ? "ok\n" : "not ok\n";

