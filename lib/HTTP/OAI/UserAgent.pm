package HTTP::OAI::UserAgent;

use vars qw(@ISA $ACCEPT $DEBUG);

use HTTP::Request;
use HTTP::Response;
use URI;
use Carp;
use File::Temp;

require LWP::UserAgent;
@ISA = qw(LWP::UserAgent);

use strict;

eval { require Compress::Zlib };
unless( $@ ) {
	$ACCEPT = "gzip";
}

$DEBUG = 0;

sub new {
	my ($class,%args) = @_;
	$DEBUG = $args{debug} if $args{debug};
	delete $args{debug};
	my $self = $class->SUPER::new(%args);
	$self;
}

sub redirect_ok { 1 }

sub request {
	my $self = shift;
	my ($request, $response);
	my $filename;
	if( ref $_[0] ) {
		($request,$filename) = @_;
	} elsif( @_ > 0 ) {
		$filename = pop() if( @_ % 2 == 1 );
		$request = HTTP::Request->new('GET', _buildurl(@_));
	} else {
		croak ref($self)."::request Requires either an HTTP::Request object or OAI arguments\n";
	}
	$filename ||= File::Temp->new( UNLINK => 1 );
	$request = $self->prepare_request($request);
	# Send Accept-Encoding if we have Zlib
	$request->headers->header('Accept-Encoding',$ACCEPT) if $ACCEPT;
warn ref($self)." GET " . $request->uri . ":\n" . $request->headers->as_string . "\n" if $DEBUG;
	eval { $response = $self->SUPER::request($request,"$filename") };
	if( $@ ) {
		if( $@ =~ /read timeout/ ) {
			$response = new HTTP::Response(504,$@);
		} else {
			$response = new HTTP::Response(500,$@);
		}
		$response->request($request);
	}
	$response->{_content_filename} = $filename;

	# Decompress the response
	$filename = decompress($response) if $ACCEPT;

	# Set the correct content-length
	$response->content_length(-s $filename);

warn ref($self)." ".$response->code." ".$response->message." ($filename): " . $response->request->uri . ":\n" . $response->headers->as_string . "\n" if $DEBUG;

	# Handle an OAI timeout
	if( $response->code eq '503' && defined($response->headers->header('Retry-After')) ) {
		if( $self->{recursion}++ > 10 ) {
			$self->{recursion} = 0;
			warn ref($self)."::request (retry-after) Given up requesting after 10 retries\n";
			return $response;
		}
		my $timeout = $response->headers->header('Retry-After');
		if( !$timeout || $timeout < 0 || $timeout > 86400 ) {
			carp ref($self)." Archive specified an odd duration to wait (\"$timeout\")";
			return $response;
		}
warn "Waiting $timeout seconds ...\n" if $DEBUG;
		sleep($timeout+5); # We wait an extra 5 secs for safety
		return request($self,@_);
	# Handle an empty response
	} elsif( $response->content_length == 0 && $response->is_success ) {
		if( $self->{recursion}++ > 10 ) {
			$self->{recursion} = 0;
			warn ref($self)."::request (empty response) Given up requesting after 10 retries\n";
			return $response;
		}
warn "Retrying on empty response ...\n" if $DEBUG;
		sleep(5);
		return request($self,@_);
	}
	$self->{recursion} = 0;
	return $response;
}

sub _buildurl {
	my %attr = @_;
	croak "Requires baseURL" unless $attr{'baseURL'};
	croak "Requires verb" unless $attr{'verb'};
	my $uri = new URI(delete($attr{'baseURL'}));
	if( defined($attr{resumptionToken}) && !$attr{force} ) {
		$uri->query_form(verb=>$attr{'verb'},resumptionToken=>$attr{'resumptionToken'});
	} else {
		delete $attr{force};
		# http://www.cshc.ubc.ca/oai/ breaks if verb isn't first, doh
		$uri->query_form(verb=>delete($attr{'verb'}),%attr);
	}
	return $uri->as_string;
}

sub url {
	my $self = shift;
	return _buildurl(@_);
}

sub decompress {
	my ($response) = @_;
	my $type = $response->headers->header("Content-Encoding");
	return $response->{_content_filename} unless defined($type);
	if( $type eq 'gzip' ) {
		my $filename = File::Temp->new( UNLINK => 1 );
		my $gz = Compress::Zlib::gzopen($response->{_content_filename}, "r") or die $!;
		my ($buffer,$c);
		my $fh = IO::File->new($filename,"w");
		binmode($fh,":utf8");
		while( ($c = $gz->gzread($buffer)) > 0 ) {
			print $fh $buffer;
		}
		$fh->close();
		$gz->gzclose();
		die "Error decompressing gziped response: " . $gz->gzerror() if -1 == $c;
		return $response->{_content_filename} = $filename;
	} else {
		die "Unsupported compression returned: $type\n";
	}
}

1;

__END__

=head1 NAME

HTTP::OAI::UserAgent - Extension of the LWP::UserAgent for OAI HTTP requests

=head1 DESCRIPTION

This module provides a simplified mechanism for making requests to an OAI repository, using the existing LWP::UserAgent module.

=head1 SYNOPSIS

	require HTTP::OAI::UserAgent;

	my $ua = new HTTP::OAI::UserAgent;

	my $response = $ua->request(
		baseURL=>'http://arXiv.org/oai1',
		verb=>'ListRecords',
		from=>'2001-08-01',
		until=>'2001-08-31'
	);

	print $response->content;

=head1 METHODS

=over 4

=item $ua = new HTTP::OAI::UserAgent(debug=>1,proxy=>'www-cache',...)

This constructor method returns a new instance of a HTTP::OAI::UserAgent module. Optionally takes a debug argument. Any other arguments are passed to the L<LWP::UserAgent|LWP::UserAgent> constructor.

=item $r = $ua->request($req)

Requests the HTTP response defined by $req, which is a L<HTTP::Request|HTTP::Request> object.

=item $r = $ua->request(baseURL=>$baseref,verb=>$verb,[from=>$from],[until=>$until],[resumptionToken=>$token],[metadataPrefix=>$mdp],[set=>$set],[oainame=>$oaivalue],...)

Makes an HTTP request to the given OAI server (baseURL) with OAI arguments. Returns an HTTP::Response object.

=item $str = $ua->url(baseURL=>$baseref,verb=>$verb,...)

Takes the same arguments as request, but returns the URL that would be requested.

=back
