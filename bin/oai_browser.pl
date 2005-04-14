#!/usr/bin/perl -w

BEGIN {
	unshift @INC, ".";
}

use vars qw($VERSION $PROTOCOL_VERSION $h);

use lib "../lib";

use HTTP::OAI;

$VERSION = $HTTP::OAI::Harvester::VERSION;

use vars qw( @ARCHIVES );
@ARCHIVES = qw(
	http://cogprints.soton.ac.uk/perl/oai2
	http://citebase.eprints.org/cgi-bin/oai2
	http://arXiv.org/oai2
	http://www.biomedcentral.com/oai/2.0/
);

use strict;
use utf8;
#use sigtrap qw( die INT ); # This is just confusing ...

#binmode(STDOUT,":encoding(iso-8859-1)"); # Causes Out of memory! errors :-(

use Getopt::Long;
use Term::ReadLine;
use Term::ReadKey;

use HTTP::OAI::Harvester;
use HTTP::OAI::Metadata::OAI_DC;

print <<EOF;
Welcome to the Open Archives Browser $VERSION

Copyright 2005 Tim Brody <tdb01r\@ecs.soton.ac.uk>

Use CTRL+C to quit at any time

---

EOF

my $SILENT = '';
my $HELP = '';
GetOptions ('silent' => \$SILENT,'help' => \$HELP);

die <<EOF if $HELP;
Usage: $0
	--help	Show this message
	--silent	Suppress the display of returned data
EOF

my $DEFAULTID = '';

use vars qw($TERM @SETS @PREFIXES);
$TERM = Term::ReadLine->new($0);
$TERM->addhistory(@ARCHIVES);

while(1) {
#	my $burl = input('Enter the base URL to use [http://cogprints.soton.ac.uk/perl/oai2]: ') || 'http://cogprints.soton.ac.uk/perl/oai2';
	my $burl = shift || $TERM->readline('OAI Base URL to query>','http://cogprints.soton.ac.uk/perl/oai2') || next;
	$h = new HTTP::OAI::Harvester(baseURL=>$burl,debug=>!$SILENT);
	if( my $r = Identify() ) {
		$h->repository($r);
		$PROTOCOL_VERSION = $r->version;
		last;
	}
}

my $archive = $h->repository;

&mainloop();

sub mainloop {
	while(1) {
		print "\nMenu\n----\n\n",
			"1. GetRecord\n2. Identify\n3. ListIdentifiers\n4. ListMetadataFormats\n5. ListRecords\n6. ListSets\nq. Quit\n\n>";
		my $cmd;
		ReadMode(4);
		while( not defined($cmd = ReadKey(-1)) ) {
			sleep(1);
		}
		ReadMode(0);
		last unless defined($cmd);
		print $cmd;
		if( $cmd eq 'q' ) {
			last;
		} elsif($cmd eq '1') {
			eval { GetRecord() };
		} elsif($cmd eq '2') {
			eval { Identify() };
		} elsif($cmd eq '3') {
			eval { ListIdentifiers() };
		} elsif($cmd eq '4') {
			eval { ListMetadataFormats() };
		} elsif($cmd eq '5') {
			eval { ListRecords() };
		} elsif($cmd eq '6') {
			eval { ListSets() };
		}
	}
}

sub GetRecord {
	printtitle("GetRecord");

	my $id = $TERM->readline("Enter the identifier to request>",$DEFAULTID) || $DEFAULTID;
	$TERM->addhistory(@PREFIXES);
	my $mdp = $TERM->readline("Enter the metadataPrefix to use>",'oai_dc') || 'oai_dc';

	my $r = $h->GetRecord(
		identifier=>$id,
		metadataPrefix=>$mdp,
		handlers=>{
			metadata=>($mdp eq 'oai_dc' ? 'HTTP::OAI::Metadata::OAI_DC' : undef),
		},
	);

	return if iserror($r);

	printheader($r);
	if( defined(my $rec = $r->next) ) {
		print "identifier => ", $rec->identifier,
			($rec->status ? " (".$rec->status.") " : ''), "\n",
			"datestamp => ", $rec->datestamp, "\n";
		foreach($rec->header->setSpec) {
			print "setSpec => ", $_, "\n";
		}
		print "\nMetadata:\n",
			$rec->metadata->toString if defined($rec->metadata);
		print "\nAbout data:\n",
			join("\n",map { $_->toString } $rec->about) if $rec->about;
	} else {
		print "Unable to extract record from OAI response (check your identifier?)\n";
	}
}

sub Identify {
	printtitle("Identify");

	my $r = $h->Identify;

	return if iserror($r);

	print map({ "adminEmail => " . $_ . "\n" } $r->adminEmail),
		"baseURL => ", $r->baseURL, "\n",
		"protocolVersion => ", $r->protocolVersion, "\n",
		"repositoryName => ", $r->repositoryName, "\n";

	foreach my $dom (grep { defined } map { $_->dom } $r->description) {
		foreach my $md ($dom->getElementsByTagNameNS('http://www.openarchives.org/OAI/2.0/oai-identifier','oai-identifier')) {
			foreach my $elem ($md->getElementsByTagNameNS('http://www.openarchives.org/OAI/2.0/oai-identifier','sampleIdentifier')) {
				$DEFAULTID = $elem->getFirstChild->toString;
				print "sampleIdentifier => ", $DEFAULTID, "\n";
			}
		}
	}

	$r;
}

sub ListIdentifiers {
	printtitle("ListIdentifiers");

	my $from = $TERM->readline("Enter an optional from period (yyyy-mm-dd)>");
	my $until = $TERM->readline("Enter an optional until period (yyyy-mm-dd)>");
	$TERM->addhistory(@SETS);
	my $set = $TERM->readline("Enter an optional set ([A-Z0-9_]+)>");
	my $mdp;
	if( $PROTOCOL_VERSION > 1.1 ) {
		$TERM->addhistory(@PREFIXES);
		$mdp = $TERM->readline("Enter the metadata prefix>",'oai_dc') || 'oai_dc';
	}

	my $r = $h->ListIdentifiers(checkargs(from=>$from,until=>$until,set=>$set,metadataPrefix=>$mdp));

	return if iserror($r);

	printheader($r);
	my $c = 0;
	while( my $rec = $r->next ) {
		return if iserror($rec);
		if( $SILENT ) {
			print STDERR $c++, "\r";
		} else {
			print "identifier => ", $rec->identifier,
				(defined($rec->datestamp) ? " / " . $rec->datestamp : ''),
				($rec->status ? " (".$rec->status.") " : ''), "\n";
		}
	}
}

sub ListMetadataFormats {
	printtitle("ListMetadataFormats");

	my $id = $TERM->readline("Enter an optional identifier>");

	my $r = $h->ListMetadataFormats(checkargs(identifier=>$id));

	return if iserror($r);
	@PREFIXES = ();

	printheader($r);
	while( my $mdf = $r->next ) {
		push @PREFIXES, $mdf->metadataPrefix;
		print "metadataPrefix => ", $mdf->metadataPrefix, "\n",
			"schema => ", $mdf->schema, "\n",
			"metadataNamespace => ", ($mdf->metadataNamespace || ''), "\n";
	}
}

sub ListRecords {
	printtitle("ListRecords");

	my $resumptionToken = $TERM->readline("Enter an optional resumptionToken>");
	my ($from, $until, $set, $mdp);
	if( !$resumptionToken ) {
		$from = $TERM->readline("Enter an optional from period (yyyy-mm-dd)>");
		$until = $TERM->readline("Enter an optional until period (yyyy-mm-dd)>");
		$TERM->addhistory(@SETS);
		$set = $TERM->readline("Enter an optional set ([A-Z0-9_]+)>");
		$TERM->addhistory(@PREFIXES);
		$mdp = $TERM->readline("Enter the metadataPrefix to use>",'oai_dc') || 'oai_dc';
	}

	my $r = $h->ListRecords(
		checkargs(resumptionToken=>$resumptionToken,from=>$from,until=>$until,set=>$set,metadataPrefix=>$mdp),
		handlers=>{
			metadata=>($mdp eq 'oai_dc' ? 'HTTP::OAI::Metadata::OAI_DC' : undef),
		},
	);

	return if iserror($r);

	printheader($r);
	my $c = 0;
	while(my $rec = $r->next) {
		return if iserror($rec);
		if( $SILENT ) {
			print STDERR $c++, "\r";
		} else {
			print "\nidentifier => ", $rec->identifier,
				($rec->status ? " (".$rec->status.") " : ''), "\n",
				"datestamp => ", $rec->datestamp, "\n";
			foreach($rec->header->setSpec) {
				print "setSpec => ", $_, "\n";
			}
			print "\nMetadata:\n",
				($rec->metadata->toString||'(null)') if $rec->metadata;
			print "\nAbout data:\n",
				join("\n",map { ($_->toString||'(null)') } $rec->about) if $rec->about;
		}
	}
}

sub ListSets {
	printtitle("ListSets");

	my $r = $h->ListSets;

	return if iserror($r);

	printheader($r);
	while(my $rec = $r->next) {
		return if iserror($rec);
		push @SETS, $rec->setSpec;
		print "setSpec => ", $rec->setSpec, "\n",
			"setName => ", $rec->setName, "\n";
	}
}

sub input {
	my $q = shift;
	print $q;
	my $r = <>;
	return unless defined($r);
	chomp($r);
	return $r;
}

sub printtitle {
	my $t = shift;
	print "\n$t\n";
	for( my $i = 0; $i < length($t); $i++ ) {
		print "-";
	}
	print "\n";
}

sub printheader {
	my $r = shift;
	print "verb => ", $r->headers->header('verb'), "\n",
		"responseDate => ", $r->headers->header('responseDate'), "\n",
		"requestURL => ", $r->headers->header('requestURL'), "\n";
}

sub checkargs {
	my %args = @_;
	foreach my $key (keys %args) {
		delete $args{$key} if( !defined($args{$key}) || $args{$key} eq '' );
	}
	%args;
}

sub iserror {
	my $r = shift;
	if( $r->is_success ) {
		return undef;
	} else {
		print "An error ", $r->code, " occurred while making the request",
			($r->request ? " (" . $r->request->uri . ") " : ''),
			":\n", $r->message, "\n";
		return 1;
	}
}
