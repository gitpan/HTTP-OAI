package HTTP::OAI::Harvester;

use strict;
use 5.005; # 5.004 seems to have problems with use base
use vars qw( @ISA $AUTOLOAD $VERSION );
use Carp;

$VERSION = '3.00';

use HTTP::OAI::UserAgent;
@ISA = qw( HTTP::OAI::UserAgent );

use HTTP::OAI::Repository; # validate_request

use HTTP::OAI::GetRecord;
use HTTP::OAI::Identify;
use HTTP::OAI::ListIdentifiers;
use HTTP::OAI::ListMetadataFormats;
use HTTP::OAI::ListRecords;
use HTTP::OAI::ListSets;

use HTTP::OAI::Error;
use HTTP::OAI::Metadata;
use HTTP::OAI::Record;
use HTTP::OAI::Set;

sub new {
	my ($class,%args) = @_;
	my %ARGS = %args;
	for(qw(baseURL resume repository)) {
		delete $ARGS{$_};
	}
	my $self = $class->SUPER::new(%ARGS);

	$self->{'resume'} = exists($args{resume}) ? $args{resume} : 1;

	$self->{repository} =
		$args{repository} ||
		HTTP::OAI::Identify->new(baseURL=>$args{baseURL});
	croak "Requires repository or baseURL" unless $self->{repository};

	$self->agent('OAI-PERL/'.$VERSION);

	return $self;
}

sub resume {
	my $self = shift;
	return @_ ? $self->{resume} = shift : $self->{resume};
}

sub repository {
	my $self = shift;
	return @_ ? $self->{repository} = shift : $self->{repository};
}

sub baseURL { shift->repository->baseURL(@_); }

sub AUTOLOAD {
	my $self = shift;
	my $name = $AUTOLOAD;
	$name =~ s/.*:://;
	return if $name eq 'DESTROY';
#	warn join(',',map { ref($_) || $_ } @_);
	if($name =~ /GetRecord|Identify|ListIdentifiers|ListMetadataFormats|ListRecords|ListSets/) {
		my %args = (
			verb=>$name,
			@_
		);
		my $handlers = $args{handlers};
		delete $args{handlers};
		if( !$args{force} &&
			defined($self->repository->version) &&
			2.0 == $self->repository->version &&
			(my @errors = HTTP::OAI::Repository::validate_request(%args)) ) {
			return new HTTP::OAI::Response(
				code=>503,
				message=>'Invalid Request (use \'force\' to force a non-conformant request): ' . $errors[0]->toString,
				errors=>\@errors
			);
		}
		delete $args{force};
		for( keys %args ) {
			delete $args{$_} if !defined($args{$_}) || !length($args{$_});
		}
		
		return "HTTP::OAI::$name"->new(
			harvestAgent=>$self,
			handlers=>$handlers,
			HTTPresponse=>$self->request(baseURL=>$self->baseURL,%args),
		);
	} else {
		my $superior = "SUPER::$name";
		return $self->$superior(@_);
	}
}

sub ListIdentifiers {
	my $self = shift;
	my %args = @_;

	if( defined $self->repository->version && 
	    $self->repository->version < 2.0 && 
	    defined $args{metadataPrefix} ) {
		delete $args{metadataPrefix};
	}

	return HTTP::OAI::ListIdentifiers->new(
		harvestAgent=>$self,
		HTTPresponse=>$self->request(
			baseURL=>$self->baseURL(),
			verb=>'ListIdentifiers',
			%args
		)
	);
}

1;

__END__

=head1 NAME

HTTP::OAI::Harvester - Agent for harvesting from an Open Archives 1.0,1.1 or 2.0 compatible repositories

=head1 DESCRIPTION

HTTP::OAI::Harvester provides the front-end to the OAI-PERL library for harvesting from OAI repositories. Direct use of the other OAI-PERL modules for harvesting should be avoided.

To harvest from an OAI-compliant repository first create the HTTP::OAI::Harvester interface using the baseURL option. It is recommended that you request an Identify from the Repository and use the repository method to update the Identify object used by the harvester.

When making OAI requests the underlying L<HTTP::OAI::UserAgent|HTTP::OAI::UserAgent> module will take care of automatic redirection (error code 302) and retry-after (error code 503).

OAI flow control (i.e. resumption tokens) is handled transparently by HTTP::OAI::Harvester.

=head1 FURTHER READING

You should refer to the Open Archives Protocol version 2.0 and other OAI documentation, available from http://www.openarchives.org/.

=head1 BEFORE USING EXAMPLES

In the examples I use arXiv.org's, and cogprints OAI interfaces. To avoid causing annoyance to their server administrators please contact them before performing testing or large downloads (or use other, less loaded, servers).

=head1 SYNOPSIS

	use HTTP::OAI;

	my $h = new HTTP::OAI::Harvester(-baseURL=>'http://arXiv.org/oai2');
	my $response = $h->repository($h->Identify)
	if( $response->is_error ) {
		print "Error requesting Identify:\n",
			$response->code . " " . $response->message, "\n";
		exit;
	}

	# Note: repositoryVersion will always be 2.0, $r->version returns
	# the actual version the repository is running
	print "Repository supports protocol version ", $response->version, "\n";

	# Version 1.x repositories don't support metadataPrefix,
	# but OAI-PERL will drop the prefix automatically
	# if an Identify was requested first (as above)
	$response = $h->ListIdentifiers(
		metadataPrefix=>'oai_dc',
		from=>'2001-02-03',
		until=>'2001-04-10'
	);

	if( $response->is_error ) {
		die("Error harvesting: " . $response->message . "\n");
	}

	print "responseDate => ", $response->responseDate, "\n",
		"requestURL => ", $response->requestURL, "\n";

	while( my $id = $response->next ) {
		if( $id->is_error ) {
			print "Error: ", $id->code, " (", $id->message, ")\n";
			last;
		}
		print "identifier => ", $id->identifier;
		# Only available from OAI 2.0 repositories
		print " (", $id->datestamp, ")" if $id->datestamp;
		print " (", $id->status, ")" if $id->status;
		print "\n";
		# Only available from OAI 2.0 repositories
		for( $id->setSpec ) {
			print "\t", $_, "\n";
		}
	}

	$response = $h->ListRecords(
		metadataPrefix=>'oai_dc',
		handlers=>{metadata=>'HTTP::OAI::Metadata::OAI_DC'},
	);
	if( $response->is_error ) {
		print "Error: ", $response->code,
			" (", $response->message, ")\n";
		exit();
	}

	while( my $rec = $response->next ) {
		if( $rec->is_error ) {
			die $rec->message;
		}
		print $rec->identifier, "\t",
			$rec->datestamp, "\n",
			$rec->metadata, "\n";
	}

=head1 METHODS

=over 4

=item $h = new HTTP::OAI::Harvester(baseURL=>'http://arXiv.org/oai1',repository=>new OAI::Identify(baseURL=>'http://cogprints.soton.ac.uk/perl/oai')[, resume=>0])

This constructor method returns a new instance of HTTP::OAI::Harvester. Requires either an L<HTTP::OAI::Identify|HTTP::OAI::Identify> object, which in turn must contain a baseURL, or a baseURL from which to construct an Identify object.

Any other options are passed to the L<HTTP::OAI::UserAgent|HTTP::OAI::UserAgent> module, and from there to the L<LWP::UserAgent|LWP::UserAgent> module.

The resume argument controls whether resumptionToken flow control is handled internally. By default this is 1. If flow control is not handled by the library programs should check the resumptionToken method to establish whether there are more records.

=item $repo = $h->repository([repo])

Returns and optionally sets the HTTP::OAI::Identify data used by the Harvester agent.

=item $r = $h->GetRecord(identifier=>'oai:arXiv:hep-th/0001001',metadataPrefix=>'oai_dc')

=item $r = $h->Identify

=item $r = $h->ListIdentifiers(metadataPrefix=>'oai_dc',-from=>'2001-10-01',until=>'2001-10-31',set=>'physics:hep-th',resumptionToken=>'xxx')

=item $r = $h->ListMetadataFormats(identifier=>'oai:arXiv:hep-th/0001001')

=item $r = $h->ListRecords(from=>'2001-10-01',until=>'2001-10-01',set=>'physics:hep-th',metadataPrefix=>'oai_dc',resumptionToken=>'xxx')

=item $r = $h->ListSets(resumptionToken=>'xxx')

These methods perform an OAI request corresponding to their name. The options are specified in the OAI protocol document, with a prepended dash. resumptionToken is exclusive and will override any other options passed to the method.

These methods either return either a:

L<HTTP::Response|HTTP::Response>

If there was a problem making the HTTP request.

Or, a module subclassed from L<HTTP::OAI::Response|HTTP::OAI::Response>, corresponding to the method name (e.g. GetRecord will return L<HTTP::OAI::GetRecord|HTTP::OAI::GetRecord>).

Use $r->is_success to determine whether an error occurred.

Use $r->code and $r->message to obtain the error code and a human-readable message. OAI level errors can be retrieved using the $r->errors method.

If the response contained an L<HTTP::OAI::ResumptionToken|HTTP::OAI::ResumptionToken> this can be retrieved using the $r->resumptionToken method.

=back

=head1 ABOUT

These modules have been written by Tim Brody E<lt>tdb01r@ecs.soton.ac.ukE<gt>.

You can find links to this and other OAI tools (perl, C++, java) at: http://www.openarchives.org/tools/tools.html.
