package HTTP::OAI::UserAgent;

use vars qw(@ISA $ACCEPT $PARSER);

# Show debug messages
our $DEBUG = 0;
# Do not use eval()
our $USE_EVAL = 1;
# Ignore bad utf8 characters
our $IGNORE_BAD_CHARS = 1;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Response;
use URI;
use Carp;
use XML::LibXML;
use Encode;

require LWP::UserAgent;
@ISA = qw(LWP::UserAgent);

unless( $@ ) {
	$ACCEPT = "gzip";
}

sub new {
	my ($class,%args) = @_;
	$DEBUG = $args{debug} if $args{debug};
	delete $args{debug};
	my $self = $class->SUPER::new(%args);
	$self;
}

sub redirect_ok { 1 }

sub request
{
	my $self = shift;
	my ($request, $arg, $size, $previous, $response) = @_;
	if( ref($request) eq 'HASH' ) {
		$request = HTTP::Request->new(GET => _buildurl(%$request));
	}
	return $self->SUPER::request(@_) unless $response;
	$PARSER = XML::LibXML->new(
		Handler => HTTP::OAI::SAXHandler->new(
			Handler => $response->headers
	));
	$PARSER->{content_length} = 0;
	$PARSER->{content_buffer} = encode('utf8','');
	$response->code(200);
	$response->message('lwp_callback');
	$response->headers->set_handler($response);
	my $r;
	warn "Requesting " . $request->uri . "\n" if $DEBUG;
	if( $USE_EVAL ) {
		eval {
			$r = $self->SUPER::request($request,\&lwp_callback);
			lwp_endparse();
		};
	} else {
		$r = $self->SUPER::request($request,\&lwp_callback);
		lwp_endparse();
	}
	if( defined($r) && defined($r->headers->header( 'Client-Aborted' )) && $r->headers->header( 'Client-Aborted' ) eq 'die' )
	{
		$r->code(500);
		$r->message( 'An error occurred while parsing: ' . $r->headers->header( 'X-Died' ));
	}

	$response->headers->set_handler(undef);
	
	# Allow access to the original headers through 'previous'
	$response->previous($r);
	
	my $cnt_len = $PARSER->{content_length};
	undef $PARSER;

	# OAI retry-after
	if( defined($r) && $r->code == 503 && defined(my $timeout = $r->headers->header('Retry-After')) ) {
		if( $self->{recursion}++ > 10 ) {
			$self->{recursion} = 0;
			warn ref($self)."::request (retry-after) Given up requesting after 10 retries\n";
			return $response->copy_from( $r );
		}
		if( !$timeout or $timeout =~ /\D/ or $timeout < 0 or $timeout > 86400 ) {
			warn ref($self)." Archive specified an odd duration to wait (\"".($timeout||'null')."\")\n";
			return $response->copy_from( $r );
		}
		warn "Waiting $timeout seconds [" . $request->uri . "]\n" if $DEBUG;
		sleep($timeout+10); # We wait an extra 10 secs for safety
		return $self->request($request,undef,undef,undef,$response);
	# Got an empty response
	} elsif( defined($r) && $r->is_success && $cnt_len == 0 ) {
		if( $self->{recursion}++ > 10 ) {
			$self->{recursion} = 0;
			warn ref($self)."::request (empty response) Given up requesting after 10 retries\n";
			return $response->copy_from( $r );
		}
		warn "Retrying on empty response [" . $request->uri . "]\n" if $DEBUG;
		sleep(5);
		return $self->request($request,undef,undef,undef,$response);
	# An HTTP error occurred
	} elsif( $r->is_error ) {
		$response->copy_from( $r );
		$response->errors(HTTP::OAI::Error->new(
			code=>$r->code,
			message=>$r->message,
		));
	# An error occurred during parsing
	} elsif( $@ ) {
		$response->code(my $code = $@ =~ /read timeout/ ? 504 : 600);
		$response->message($@);
		$response->errors(HTTP::OAI::Error->new(
			code=>$code,
			message=>$@,
		));
	}

	# Reset the recursion timer
	$self->{recursion} = 0;
	
	# Copy original $request => OAI $response to allow easy
	# access to the requested URL
	$response->request($request);
	$response;
}

sub lwp_endparse
{
	my $utf8 = $PARSER->{content_buffer};
	# Replace bad chars with '?'
	if( $IGNORE_BAD_CHARS and length($utf8) ) {
		$utf8 = decode('utf8', $utf8, Encode::FB_PERLQQ|Encode::FB_WARN);
		_ccchars(\$utf8); # Fix control chars
	}
	if( length($utf8) > 0 )
	{
		$PARSER->{content_length} += length($utf8);
		$PARSER->parse_chunk($utf8);
	}
	delete($PARSER->{content_buffer});
	$PARSER->parse_chunk('', 1);
}

sub lwp_callback
{
	$PARSER->{content_buffer} .= $_[0];
	# FB_QUIET won't split multi-byte chars on input
	my $utf8 = decode('utf8', $PARSER->{content_buffer}, Encode::FB_QUIET);
	_ccchars(\$utf8); # Fix control chars
	if( length($utf8) > 0 )
	{
		$PARSER->{content_length} += length($utf8);
		$PARSER->parse_chunk($utf8);
	}
}

sub _ccchars {
	my $str = shift;
	$$str =~ s/([\x00-\x08\x0b-\x0c\x0e-\x1f])/sprintf("\\%04d",ord($1))/seg;
}

sub _buildurl {
	my %attr = @_;
	croak "_buildurl requires baseURL" unless $attr{'baseURL'};
	croak "_buildurl requires verb" unless $attr{'verb'};
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
