package HTTP::OAI::Response;

use vars qw($BAD_REPLACEMENT_CHAR @ISA);

use utf8;

use HTTP::Response;
use XML::SAX::Base;
use XML::LibXML;
use POSIX qw/strftime/;
use Carp;
use URI;

use CGI;

use HTTP::OAI::Headers;
use HTTP::OAI::Error;
use HTTP::OAI::SAXHandler qw/ :SAX /;

@ISA = qw( HTTP::Response XML::SAX::Base );
$BAD_REPLACEMENT_CHAR = '?';

# Attempt to get the time zone offset (+hh:mm)

sub new {
	my ($class,%args) = @_;
	$args{headers} = new HTTP::OAI::Headers();
	$args{errors} ||= [];
	$args{resume} = 1 unless exists $args{resume};
	$args{handlers} ||= {};
	my $self = bless \%args, ref($class) || $class;

	# Force the version of OAI to try to parse
	$self->version($args{version});

	# HTTP::Response initialisation
	if( $args{code} ) {
		$self->code($args{code});
	}
	if( $args{message} ) {
		$self->message($args{message});
	}

	# Parse an OAI response
	if( $args{HTTPresponse} ) {
		$self->initialize_HTTPresponse($args{HTTPresponse});
	}

	# OAI initialisation
	if( $args{responseDate} ) {
		$self->responseDate($args{responseDate});
	}
	if( $args{requestURL} ) {
		$self->requestURL($args{requestURL});
	}
	if( $args{xslt} ) {
		$self->xslt($args{xslt});
	}

	# Do some intelligent filling of undefined values
	unless( defined($self->responseDate) ) {
		$self->responseDate(strftime("%Y-%m-%dT%H:%M:%S",gmtime).'Z');
	}
	unless( defined($self->requestURL) ) {
		$self->requestURL(CGI->new()->self_url());
	}
	unless( defined($self->verb) ) {
		my $verb = ref($self);
		$verb =~ s/.*:://;
		$self->verb($verb);
	}

	return $self;
}

sub initialize_HTTPresponse {
	my ($self, $r) = @_;

	$self->{_content} = ${$r->content_ref};
	$self->{_content_filename} = $r->{_content_filename};
	$self->{_headers} = $r->headers;

	$self->code($r->code);
	$self->message($r->message);
	$self->request($r->request);
	$self->previous($r->previous);

	return if $self->is_error;

	if( $self->content_length == 0 ) {
		$self->code(600);
		$self->message('The server response didn\'t contain anything');
		$self->errors(
			HTTP::OAI::Error->new(
				code=>'emptyResponse',
				message=>'The server response didn\'t contain anything'
			));
	} else {
		my %args = URI->new($self->request->uri)->query_form;
		$self->headers->header('_args',\%args); # Used to parse static repositories (which the Headers filter for)
	
		my $fh = IO::File->new($self->{_content_filename},"r") or die "Unable to open downloaded response for reading ($fn): $!";
		$self->parse_file($fh);
		$fh->close;
	}
}

sub parse_file {
	my ($self, $fh) = @_;

	my $handler = new HTTP::OAI::SAXHandler();
	$handler->set_handler($self->headers);
	$self->headers->set_handler($self);
	my $parser = XML::LibXML::SAX->new(Handler=>$handler);

	eval { $parser->parse_file($fh) };

	if( $@ ) {
		$self->code(600);
		my $msg = $@;
		$msg =~ s/^\s+//s;
		$msg =~ s/\s+$//s;
		if( $self->request ) {
			$msg = "Error parsing XML from " . $self->request->uri . " " . $msg;
		} else {
			$msg = "Error parsing XML from string: $msg\n";
		}
		$self->message($msg);
		$self->errors(new HTTP::OAI::Error(
				code=>'parseError',
				message=>$msg
			));
	}
}

sub parse_string {
	my ($self, $str) = @_;

	do {
		my $handler = new HTTP::OAI::SAXHandler();
		$handler->set_handler($self->headers);
		$self->headers->set_handler($self);
		my $parser = XML::LibXML::SAX->new(Handler=>$handler);

		eval { $parser->parse_string($str) };
		if( $@ ) {
			$self->errors(new HTTP::OAI::Error(
				code=>'parseError',
				message=>"Error while parsing XML: $@",
			));
		}
	} while( $@ && fix_xml(\$str,$@) );
	if( $@ ) {
		$self->code(600);
		my $msg = $@;
		$msg =~ s/^\s+//s;
		$msg =~ s/\s+$//s;
		if( $self->request ) {
			$msg = "Error parsing XML from " . $self->request->uri . " " . $msg;
		} else {
			$msg = "Error parsing XML from string: $msg\n";
		}
		$self->message($msg);
		$self->errors(new HTTP::OAI::Error(
				code=>'parseError',
				message=>$msg
			));
		return;
	}
}

sub harvestAgent {
	return shift->{harvestAgent};
}

# Resume a request using a resumptionToken
sub resume {
	my ($self,%args) = @_;
	my $ha = $args{harvestAgent} || $self->harvestAgent || croak ref($self)."::resume Required argument harvestAgent is undefined";
	my $token = $args{resumptionToken} || croak ref($self)."::resume Required argument resumptionToken is undefined";
	my $verb = $args{verb} || $self->verb || croak ref($self)."::resume Required argument verb is undefined";

	my $tries = 5;
	my $response;

	# Retry the request 5 times (leave a minute between retries)
	do {
		$response = $ha->request(
			baseURL=>$ha->repository->baseURL,
			verb=>$verb,
			resumptionToken=>(ref $token ? $token->resumptionToken : $token)
		);
	} while( $tries-- && $response->is_error && sleep(60) );

	$self->resumptionToken(undef);

	$self->initialize_HTTPresponse($response);

	if( $self->resumptionToken &&
		defined($self->resumptionToken->resumptionToken) &&
		($self->resumptionToken->resumptionToken eq $token->resumptionToken) ) {
		$self->code(600);
		$self->message("Flow-control error: Resumption token hasn't changed (" . $response->request->uri . ").");
	}

	$self;
}

sub generate {
	my ($self) = @_;
	return unless defined(my $handler = $self->get_handler);
	$self->headers->set_handler($handler);

	$handler->start_document();
	$handler->xml_decl({'Version'=>'1.0','Encoding'=>'UTF-8'});
	$handler->characters({'Data'=>"\n"});
	if( $self->xslt ) {
		$handler->processing_instruction({
			'Target' => 'xml-stylesheet',
			'Data' => 'type=\'text/xsl\' href=\''. $self->xslt . '\''
		});
	}
	$self->headers->generate_start();

	if( $self->errors ) {
		for( $self->errors ) {
			$_->set_handler($handler);
			$_->generate();
		}
	} else {
		g_start_element($handler,'http://www.openarchives.org/OAI/2.0/',$self->verb,{});
		$self->generate_body();
		g_end_element($handler,'http://www.openarchives.org/OAI/2.0/',$self->verb,{});
	}
	
	$self->headers->generate_end();
	$handler->end_document();
}

sub toDOM {
	my $self = shift;
	$self->set_handler(my $builder = XML::LibXML::SAX::Builder->new());
	$self->generate();
	$builder->result;
}

sub headers { shift->{headers} }
sub errors {
	my $self = shift;
	push @{$self->{errors}}, @_;
	for (@_) {
		if( $_->code eq 'badVerb' || $_->code eq 'badArgument' ) {
			my $uri = URI->new($self->requestURL || '');
			$uri->query('');
			$self->requestURL($uri->as_string);
			last;
		}
	}
	@{$self->{errors}};
}

sub responseDate { shift->headers->header('responseDate',@_) }
sub requestURL { shift->headers->header('requestURL',@_) }
sub xslt { shift->headers->header('xslt',@_) }

sub verb { shift->headers->header('verb',@_) }
sub version { shift->headers->header('version',@_) }

sub is_error {
	my $self = shift;
	# HTTP::Response doesn't return error if code = 0
	return $self->code != 200;
}

sub end_element {
	my ($self,$hash) = @_;
	my $elem = $hash->{Name};
	$self->SUPER::end_element($hash);
	if( $elem eq 'error' ) {
		my $code = $hash->{Attributes}->{'{}code'}->{'Value'} || 'oai-lib: Undefined error code';
		my $msg = $hash->{Text} || 'oai-lib: Undefined error message';
		$self->errors(new HTTP::OAI::Error(
			code=>$code,
			message=>$msg,
		));
		if( $code ne 'noRecordsMatch' ) {
			$self->verb($elem);
			$self->code(600);
			$self->message("Response contains error(s): " . $self->{errors}->[0]->code . " (" . $self->{errors}->[0]->message . ")");
		}
	}
}

sub fix_xml {
	my ($str, $err) = @_;
	return 0 unless( $err =~ /not well-formed.*byte (\d+)/ );
        my $offset = $1;
        if( substr($$str,$offset-1,1) eq '&' ) {
                substr($$str,$offset-1,1) = '&amp;';
                return 1;
        } elsif( substr($$str,$offset-1,1) eq '<' ) {
                substr($$str,$offset-1,1) = '&lt;';
                return 1;
        } elsif( substr($$str,$offset,1) ne $BAD_REPLACEMENT_CHAR ) {
                substr($$str,$offset,1) = $BAD_REPLACEMENT_CHAR;
                return 1;
        } else {
                return 0;
        }
}

1;

__END__

=head1 NAME

HTTP::OAI::Response - An OAI response

=head1 METHODS

=over 4

=item $r = new HTTP::OAI::Response([-responseDate=>$rd][, -requestURL=>$ru])

This constructor method returns a new HTTP::OAI::Response object. Optionally set the responseDate and requestURL.

Use $r->is_error to test whether the request was successful. In addition to the HTTP response codes, the following codes may be returned:

600 - Error parsing XML or invalid OAI response

Use $r->message to obtain a human-readable error message.

=item $headers = $r->headers

Returns the embedded L<HTTP::OAI::Headers|HTTP::OAI::Headers> object.

=item $r->code

=item $r->message

Returns the HTTP code (600 if there was an error with the OAI response) and a human-readable message.

=item $errs = $r->errors([$err])

Returns and optionally adds to the OAI error list. Returns a reference to an array.

=item $rd = $r->responseDate([$rd])

=item $ru = $r->requestURL([$ru])

=item $verb = $r->verb([$verb])

These methods are wrappers around the Header fields of the same name.

=item $r->version

Return the version of the OAI protocol used by the remote site (protocolVersion is automatically changed by the underlying API).

=back

=head1 NOTE - requestURI/request

Version 2.0 of OAI uses a "request" element to contain the client's request, rather than a URI. The OAI-PERL library automatically converts from a URI into the appropriate request structure, and back again when harvesting.

The exception to this rule is for badVerb errors, where the arguments will not be available for conversion into a URI.
