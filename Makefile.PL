require 5.005;
use ExtUtils::MakeMaker;

# n.b. I put 0.1 as version requirements as I have
# very recent versions, whereas these modules will
# most likely work with older versions of the req.
# modules. TDB

WriteMakefile(
	NAME		=> 'HTTP-OAI',
	VERSION_FROM	=> 'lib/HTTP/OAI/Harvester.pm',
	EXE_FILES	=> [ qw( bin/oai_browser.pl ) ],
	PREREQ_PM	=> {
				'XML::LibXML' => 1.58,
				'XML::SAX::Base' => 1.00,
				'URI' => 0.1,
				'Term::ReadKey' => 0.1,
				'File::Temp' => 0.14,
				'HTTP::Request' => 0.1,
				'HTTP::Response' => 0.1,
				'LWP::UserAgent' => 0.1,
				'Test::More' => 0.1,
			},
	dist		=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
);
