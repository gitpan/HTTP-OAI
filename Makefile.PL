require 5.005;
use ExtUtils::MakeMaker;

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
			},
	dist		=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
);
