package HTTP::OAI::Repository;

use strict;
use 5.005; # 5.004 seems to have problems with use base
use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw();
@EXPORT_OK = qw( validate_request &validate_request_1_1 &validate_date &validate_metadataPrefix &validate_responseDate &validate_setSpec );
%EXPORT_TAGS = (validate=>[qw(&validate_request &validate_date &validate_metadataPrefix &validate_responseDate &validate_setSpec)]);

use HTTP::OAI::Error qw(%OAI_ERRORS);

# Copied from Simeon Warner's tutorial at
# http://library.cern.ch/HEPLW/4/papers/3/OAIServer.pm
# (note: corrected grammer for ListSets)
# 0 = optional, 1 = required, 2 = exclusive
my %grammer = (
	'GetRecord' =>
	{
		'identifier' => [1, \&validate_identifier],
		'metadataPrefix' => [1, \&validate_metadataPrefix]
	},
	'Identify' => {},
	'ListIdentifiers' =>
	{
		'from' => [0, \&validate_date],
		'until' => [0, \&validate_date],
		'set' => [0, \&validate_setSpec_2_0],
		'metadataPrefix' => [1, \&validate_metadataPrefix],
		'resumptionToken' => [2, sub { 1 }]
	},
	'ListMetadataFormats' =>
	{
		'identifier' => [0, \&validate_identifier]
	},
	'ListRecords' =>
	{
		'from' => [0, \&validate_date],
		'until' => [0, \&validate_date],
		'set' => [0, \&validate_setSpec_2_0],
		'metadataPrefix' => [1, \&validate_metadataPrefix],
		'resumptionToken' => [2, sub { 1 }]
	},
	'ListSets' =>
	{
		'resumptionToken' => [2, sub { 1 }]
	}
);

sub new {
	my ($class,%args) = @_;
	my $self = bless {}, $class;
	$self;
}

sub validate_request { validate_request_2_0(@_); }

sub validate_request_2_0 {
	my %params = @_;
	my $verb = $params{'verb'};
	delete $params{'verb'};

	my @errors;

	return (new HTTP::OAI::Error(code=>'badVerb',message=>'No verb supplied')) unless defined $verb;

	my $grm = $grammer{$verb} or return (new HTTP::OAI::Error(code=>'badVerb',message=>"Unknown verb '$verb'"));

	if( defined $params{'from'} && defined $params{'until'} ) {
		if( granularity($params{'from'}) ne granularity($params{'until'}) ) {
			return (new HTTP::OAI::Error(
				code=>'badArgument',
				message=>'Granularity used in from and until must be the same'
			));
		}
	}

	# Check exclusivity
	foreach my $arg (keys %$grm) {
		my ($type, $valid) = @{$grm->{$arg}};
		next unless ($type == 2 && defined($params{$arg}));

		return (new HTTP::OAI::Error(code=>'badArgument'))
			unless &$valid($params{$arg});

		delete $params{$arg};
		if( %params ) {
			for(keys %params) {
				push @errors, new HTTP::OAI::Error(code=>'badArgument',message=>"'$_' can not be used in conjunction with $arg");
			}
			return @errors;
		} else {
			return ();
		}
	}

	# Check required/optional
	foreach my $arg (keys %$grm) {
		my ($type, $valid) = @{$grm->{$arg}};

		if( $params{$arg} ) {
			return (new HTTP::OAI::Error(code=>'badArgument'))
				unless &$valid($params{$arg});
		}
		if( $type == 1 && (!defined($params{$arg}) || $params{$arg} eq '') ) {
			return (new HTTP::OAI::Error(code=>'badArgument',message=>"Required argument '$arg' was undefined"));
		}
		delete $params{$arg};
	}

	if( %params ) {
		for(keys %params) {
			push @errors, new HTTP::OAI::Error(code=>'badArgument',message=>"'$_' is not a recognised argument for $verb");
		}
		return @errors;
	} else {
		return ();
	}
}

sub granularity {
	my $date = shift;
	return 'year' if $date =~ /^\d{4}-\d{2}-\d{2}$/;
	return 'seconds' if $date =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
}

sub validate_date {
	my $date = shift;
	return unless $date =~ /^(\d{4})-(\d{2})-(\d{2})(T\d{2}:\d{2}:\d{2}Z)?$/;
	my( $y, $m, $d ) = ($1,($2||1),($3||1));
	return if ($m < 1 || $m > 12);
	return if ($d < 1 || $d > 31);
	1;
}

sub validate_responseDate {
	my $dt = shift;
	return unless $dt =~ /^(\d{4})\-([01][0-9])\-([0-3][0-9])T([0-2][0-9]):([0-5][0-9]):([0-5][0-9])[\+\-]([0-2][0-9]):([0-5][0-9])$/;
	return 1;
}

sub validate_setSpec {
	my $set = shift;
	return unless $set =~ /^([A-Za-z0-9])+(:[A-Za-z0-9]+)*$/;
	1;
}

sub validate_setSpec_2_0 {
	return shift =~ /([A-Za-z0-9_!'\$\(\)\+\-\.\*])+(:[A-Za-z0-9_!'\$\(\)\+\-\.\*]+)*/;
}

sub validate_metadataPrefix {
	return shift =~ /^[\w]+$/;
}

# OAI 2 requires identifiers by valid URIs
# This doesn't check for invalid chars, merely <sheme>:<scheme-specific>
sub validate_identifier {
	return shift =~ /^[[:alpha:]][[:alnum:]\+\-\.]*:.+/;
}
1;

__END__

=head1 NAME

HTTP::OAI::Repository - Documentation for building an OAI compliant repository using OAI-PERL

=head1 DESCRIPTION

Using the OAI-PERL library in a repository context requires the user to build the OAI responses to be sent to OAI harvesters.

=head1 SYNOPSIS 1

	use HTTP::OAI::Harvester;
	use HTTP::OAI::Metadata::OAI_DC;
	use XML::SAX::Writer;
	use XML::LibXML;

	# (all of these options _must_ be supplied to comply with the OAI protocol)
	# (protocolVersion and responseDate both have sensible defaults)
	my $r = new HTTP::OAI::Identify(
		baseURL=>'http://yourhost/cgi/oai',
		adminEmail=>'youremail@yourhost',
		repositoryName=>'agoodname',
		requestURL=>self_url()
	);

	# Include a description (an XML::LibXML Dom object)
	$r->description(new HTTP::OAI::Metadata(dom=>$dom));

	my $r = HTTP::OAI::GetRecord->new(
		header=>HTTP::OAI::Header->new(
			identifier=>'oai:myrepo:10',
			datestamp=>'2004-10-01'
			),
		metadata=>HTTP::OAI::Metadata::OAI_DC->new(
			dc=>{title=>['Hello, World!'],description=>['My Record']}
			)
	);
	$r->about(HTTP::OAI::Metadata->new(dom=>$dom));

	my $writer = XML::SAX::Writer->new();
	$r->set_handler($writer);
	$r->generate;

=head1 Building an OAI compliant repository

The validation scripts included in this module provide the repository admin with a number of tools for helping with being OAI compliant, however they can not be exhaustive in themselves.

=head1 METHODS

=over 4

=item $r = HTTP::OAI::Repository::validate_request(%paramlist)

=item $r = HTTP::OAI::Repository::validate_request_2_0(%paramlist)

These functions, exported by the Repository module, validate an OAI request against the protocol requirements. Returns an L<HTTP::Response|HTTP::Response> object, with the code set to 200 if the request is well-formed, or an error code and the message set.

e.g:

	my $r = validate_request(%paramlist);

	print header(-status=>$r->code.' '.$r->message),
		$r->error_as_HTML;

Note that validate_request attempts to be as strict to the Protocol as possible.

=item $b = HTTP::OAI::Repository::validate_date($date)

=item $b = HTTP::OAI::Repository::validate_metadataPrefix($mdp)

=item $b = HTTP::OAI::Repository::validate_responseDate($date)

=item $b = HTTP::OAI::Repository::validate_setSpec($set)

These functions, exported by the Repository module, validate the given type of OAI data. Returns true if the given value is sane, false otherwise.

=back

=head1 EXAMPLE

See the bin/gateway.pl for an example implementation (it's actually for creating a static repository gateway, but you get the idea!).
