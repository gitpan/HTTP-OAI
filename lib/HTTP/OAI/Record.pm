package HTTP::OAI::Record;

use vars qw(@ISA);

use HTTP::OAI::Metadata;
use HTTP::OAI::Header;
use HTTP::OAI::Metadata;
use HTTP::OAI::SAXHandler qw/ :SAX /;

@ISA = qw(HTTP::OAI::Encapsulation);

sub new {
	my ($class,%args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{handlers} = $args{handlers};

	$self->header($args{header}) unless defined($self->header);
	$self->metadata($args{metadata}) unless defined($self->metadata);
	$self->{about} = $args{about} || [] unless defined($self->{about});

	$self->header(new HTTP::OAI::Header(%args)) unless defined $self->header;

	$self;
}

sub header { shift->_elem('header',@_) }
sub metadata { shift->_elem('metadata',@_) }
sub about {
	my $self = shift;
	push @{$self->{about}}, @_ if @_;
	return @{$self->{about}};
}

sub identifier { shift->header->identifier(@_) }
sub datestamp { shift->header->datestamp(@_) }
sub status { shift->header->status(@_) }

sub generate {
	my ($self) = @_;
	return unless defined(my $handler = $self->get_handler);

	g_start_element($handler,'http://www.openarchives.org/OAI/2.0/','record',{});
	$self->header->set_handler($handler);
	$self->header->generate;
	g_data_element($handler,'http://www.openarchives.org/OAI/2.0/','metadata',{},$self->metadata) if defined($self->metadata);
	g_data_element($handler,'http://www.openarchives.org/OAI/2.0/','about',{},$_) for $self->about;
	g_end_element($handler,'http://www.openarchives.org/OAI/2.0/','record');
}

sub start_element {
	my ($self,$hash) = @_;
	my $elem = lc($hash->{LocalName});
die unless $self->version;
	if( defined($self->get_handler()) ) {
		if( $elem =~ /header|metadata|about/ ) {
			$self->{"in_$elem"}++;
		}
	} elsif( $elem eq 'record' && $self->version eq '1.1' ) {
		$self->status($hash->{Attributes}->{'{}status'}->{Value});
	} elsif( $elem =~ /header|metadata|about/ ) {
		$self->set_handler(my $handler = $self->{handlers}->{$elem}->new());
		$self->header($handler) if $elem eq 'header';
		$self->metadata($handler) if $elem eq 'metadata';
		$self->about($handler) if $elem eq 'about';
		$self->SUPER::start_document();
		$self->{"in_$elem"} = $hash->{Depth};
	}
	$self->SUPER::start_element($hash);
}

sub end_element {
	my ($self,$hash) = @_;
	my $elem = lc($hash->{LocalName});
	$self->SUPER::end_element($hash);
	if( defined($self->get_handler()) && $elem =~ /header|metadata|about/ ) {
		if( $self->{"in_$elem"} == $hash->{Depth} ) {
			$self->SUPER::end_document();
			$self->set_handler(undef);
		}
		$self->{"in_$elem"} = undef;
	}
}

1;

__END__

=head1 NAME

HTTP::OAI::Record - Encapsulates OAI record XML data

=head1 SYNOPSIS

	use HTTP::OAI::Record;

	# Create a new HTTP::OAI Record
	my $r = new HTTP::OAI::Record();

	$r->header->identifier('oai:myarchive.org:oid-233');
	$r->header->datestamp('2002-04-01');
	$r->header->setSpec('all:novels');
	$r->header->setSpec('all:books');

	$r->metadata(new HTTP::OAI::Metadata(dom=>$md));
	$r->about(new HTTP::OAI::Metadata(dom=>$ab));

=head1 METHODS

=over 4

=item $r = new HTTP::OAI::Record([header=>$header],[metadata=>$metadata],[about=>[$about]])

This constructor method returns a new HTTP::OAI::Record object. Optionally set the header, metadata, and add an about.

=item $r->header([HTTP::OAI::Header])

Returns and optionally sets the record header (an L<HTTP::OAI::Header|HTTP::OAI::Header> object).

=item $r->metadata([HTTP::OAI::Metadata])

Returns and optionally sets the record metadata (an L<HTTP::OAI::Metadata|HTTP::OAI::Metadata> object).

=item $r->about([HTTP::OAI::Metadata])

Optionally adds a new About record (an L<HTTP::OAI::Metadata|HTTP::OAI::Metadata> object) and returns a list of about returns.

=back
