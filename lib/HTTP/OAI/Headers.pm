package HTTP::OAI::Headers;

use URI;

use HTTP::OAI::SAXHandler qw( :SAX );

use vars qw( @ISA );

@ISA = qw( XML::SAX::Base );

my %VERSIONS = (
	'http://www.openarchives.org/oai/1.0/oai_getrecord' => '1.0',
	'http://www.openarchives.org/oai/1.0/oai_identify' => '1.0',
	'http://www.openarchives.org/oai/1.0/oai_listidentifiers' => '1.0',
	'http://www.openarchives.org/oai/1.0/oai_listmetadataformats' => '1.0',
	'http://www.openarchives.org/oai/1.0/oai_listrecords' => '1.0',
	'http://www.openarchives.org/oai/1.0/oai_listsets' => '1.0',
	'http://www.openarchives.org/oai/1.1/oai_getrecord' => '1.1',
	'http://www.openarchives.org/oai/1.1/oai_identify' => '1.1',
	'http://www.openarchives.org/oai/1.1/oai_listidentifiers' => '1.1',
	'http://www.openarchives.org/oai/1.1/oai_listmetadataformats' => '1.1',
	'http://www.openarchives.org/oai/1.1/oai_listrecords' => '1.1',
	'http://www.openarchives.org/oai/1.1/oai_listsets' => '1.1',
	'http://www.openarchives.org/oai/2.0/' => '2.0',
);

sub new {
	my $class = shift;
	my $self = bless {
		'field'=>{
			'xmlns'=>'http://www.openarchives.org/OAI/2.0/',
			'xmlns:xsi'=>'http://www.w3.org/2001/XMLSchema-instance',
			'xsi:schemaLocation'=>'http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd'
		},
	}, ref($class) || $class;
	return $self;
}

sub generate_start {
	my ($self) = @_;
	return unless defined(my $handler = $self->get_handler);

	$handler->start_prefix_mapping({
			'Prefix'=>'xsi',
			'NamespaceURI'=>'http://www.w3.org/2001/XMLSchema-instance'
		});
	$handler->start_prefix_mapping({
			'Prefix'=>'',
			'NamespaceURI'=>'http://www.openarchives.org/OAI/2.0/'
		});
	g_start_element($handler,
		'http://www.openarchives.org/OAI/2.0/',
		'OAI-PMH',
			{
				'{http://www.w3.org/2001/XMLSchema-instance}schemaLocation'=>{
					'LocalName' => 'schemaLocation',
					'Prefix' => 'xsi',
					'Value' => 'http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd',
					'Name' => 'xsi:schemaLocation',
					'NamespaceURI' => 'http://www.w3.org/2001/XMLSchema-instance',
				},
				'{}xmlns' => {
					'Prefix' => '',
					'LocalName' => 'xmlns',
					'Value' => 'http://www.openarchives.org/OAI/2.0/',
					'Name' => 'xmlns',
					'NamespaceURI' => '',
				},
				'{http://www.w3.org/2000/xmlns/}xsi'=>{
					'LocalName' => 'xsi',
					'Prefix' => 'xmlns',
					'Value' => 'http://www.w3.org/2001/XMLSchema-instance',
					'Name' => 'xmlns:xsi',
					'NamespaceURI' => 'http://www.w3.org/2000/xmlns/',
				},
			});

	g_data_element($handler,
		'http://www.openarchives.org/OAI/2.0/',
		'responseDate',
		{},
		$self->header('responseDate')
	);
	
	my $uri = new URI($self->header('requestURL'));
	my $attr;
	my %QUERY = $uri->query_form;
	while(my ($key,$value) = each %QUERY) {
		$attr->{"{}$key"} = {'Name'=>$key,'LocalName'=>$key,'Value'=>$value,'Prefix'=>'','NamespaceURI'=>''};
	}
	g_data_element($handler,
		'http://www.openarchives.org/OAI/2.0/',
		'request',
		$attr,
		$uri->query ?
			substr($uri->as_string(),0,length($uri->as_string())-length($uri->query)-1) :
			$uri->as_string
	);
}

sub generate_end {
	my ($self) = @_;
	return unless defined(my $handler = $self->get_handler);

	g_end_element($handler,
		'http://www.openarchives.org/OAI/2.0/',
		'OAI-PMH'
	);

	$handler->end_prefix_mapping({
			'Prefix'=>'xsi',
			'NamespaceURI'=>'http://www.w3.org/2001/XMLSchema-instance'
		});
	$handler->end_prefix_mapping({
			'Prefix'=>'',
			'NamespaceURI'=>'http://www.openarchives.org/OAI/2.0/'
		});
}

sub header {
	my $self = shift;
	return @_ > 1 ? $self->{field}->{$_[0]} = $_[1] : $self->{field}->{$_[0]};
}

sub start_element {
	my ($self,$hash) = @_;
	return $self->SUPER::start_element($hash) if $self->{State};
	my $elem = $hash->{Name};
	my $attr = $hash->{Attributes};

	# Root element
	my $xmlns = $attr->{'{}xmlns'};
	unless(
		defined($xmlns) &&
		defined($xmlns->{'Value'}) &&
		$self->header('version',$VERSIONS{lc($xmlns->{'Value'})})
	) {
		die "Error parsing response: Unknown or unsupported OAI version (" . ($attr->{'{}xmlns'} || 'No xmlns given') . ").";
	}
	$self->{State} = 1;
}

sub end_element {
	my ($self,$hash) = @_;
	my $elem = $hash->{Name};
	my $attr = $hash->{Attributes};
	my $text = $hash->{Text};
	$self->SUPER::end_element($hash);
	if( $elem eq 'responseDate' || $elem eq 'requestURL' ) {
		$self->header($elem,$text);
	} elsif( $elem eq 'request' ) {
		$self->header("request",$text);
		my $uri = new URI($text);
		$uri->query_form(map { ($_,$attr->{$_}->{Value}) } keys %$attr);
		$self->header("requestURL",$uri);
	} else {
		die "Still in headers, but came across an unrecognised element: $elem";
	}
	if( $elem eq 'requestURL' || $elem eq 'request' ) {
		die "Oops! Root handler isn't $self ($hash->{State})"
			unless ref($self) eq ref($hash->{State}->get_handler);
		$hash->{State}->set_handler($self->get_handler);
	}
	return 1;
}

1;

__END__

=head1 NAME

HTTP::OAI::Headers - Encapsulation of 'header' values

=head1 METHODS

=over 4

=item $value = $hdrs->header($name,[$value])

Return and optionally set the header field $name to $value.

=back
