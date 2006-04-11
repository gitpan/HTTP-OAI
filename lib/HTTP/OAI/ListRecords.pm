package HTTP::OAI::ListRecords;

use HTTP::OAI::Record;
use HTTP::OAI::ResumptionToken;

use HTTP::OAI::Response;

use vars qw( @ISA );
@ISA = qw( HTTP::OAI::Response );

sub new {
	my ($class,%args) = @_;
	
	$args{handlers} ||= {};
	$args{handlers}->{header} ||= "HTTP::OAI::Header";
	$args{handlers}->{metadata} ||= "HTTP::OAI::Metadata";
	$args{handlers}->{about} ||= "HTTP::OAI::Metadata";

	my $self = $class->SUPER::new(%args);
	
	$self->{record} ||= [];
	$self->{onRecord} = $args{onRecord};

	$self;
}

sub resumptionToken { shift->headers->header('resumptionToken',@_) }

sub record {
	my $self = shift;
	return $self->{onRecord}->($_[0]) if @_ and defined($self->{onRecord});
	push(@{$self->{record}}, @_);
	return wantarray ?
		@{$self->{record}} :
		$self->{record}->[0];
}

sub next {
	my $self = shift;
	return shift @{$self->{record}} if @{$self->{record}};
	return undef if (!$self->resumptionToken or $self->resumptionToken->is_empty or !$self->harvestAgent->resume);

	$self->resume(resumptionToken=>$self->resumptionToken);
	return $self->is_success ? $self->next : undef;
}

sub generate_body {
	my ($self) = @_;
	return unless defined(my $handler = $self->get_handler);

	for( $self->record ) {
		$_->set_handler($self->get_handler);
		$_->generate;
	}
	if( defined($self->resumptionToken) ) {
		$self->resumptionToken->set_handler($handler);
		$self->resumptionToken->generate;
	}
}

sub start_element {
	my ($self,$hash) = @_;
	my $elem = lc($hash->{LocalName});
	if( $elem eq 'record' ) {
		if( !$self->{"in_record"} ) {
			my $rec = new HTTP::OAI::Record(
					version=>$self->version,
					handlers=>$self->{handlers},
			);
			$self->set_handler($rec);
			$self->{"in_record"} = $hash->{Depth};
		}
	} elsif( $elem eq 'resumptiontoken' ) {
		$self->resumptionToken(my $rt = new HTTP::OAI::ResumptionToken(version=>$self->version));
		$self->set_handler($rt);
	}
	$self->SUPER::start_element($hash);
}

sub end_element {
	my ($self,$hash) = @_;
	my $elem = lc($hash->{LocalName});
	$self->SUPER::end_element($hash);
	if( $elem eq 'record' and $self->{"in_record"} == $hash->{Depth} ) {
		$self->record( $self->get_handler );
		$self->set_handler( undef );
		$self->{"in_record"} = 0;
	}
}

1;

__END__

=head1 NAME

HTTP::OAI::ListRecords - Provide access to an OAI ListRecords response

=head1 SYNOPSIS

	my $r = $h->ListRecords(
		metadataPrefix=>'oai_dc',
	);

	while( my $rec = $r->next ) {
		print "Identifier => ", $rec->identifier, "\n";
	}
	
	die $r->message if $r->is_error;

	# Using callback method
	sub callback {
		my $rec = shift;
		print "Identifier => ", $rec->identifier, "\n";
	};
	my $r = $h->ListRecords(
		metadataPrefix=>'oai_dc',
		onRecord=>\&callback
	);
	while( $r->next ) {}
	die $r->message if $r->is_error;
	
=head1 METHODS

=over 4

=item $lr = new HTTP::OAI::ListRecords

This constructor method returns a new HTTP::OAI::ListRecords object.

=item $rec = $lr->next

Returns either an L<HTTP::OAI::Record|HTTP::OAI::Record> object, or undef, if no more record are available. Use $rec->is_error to test whether there was an error getting the next record.

=item @recl = $lr->record([$rec])

Returns the record list and optionally adds a new record or resumptionToken, $rec. Returns an array ref of L<HTTP::OAI::Record|HTTP::OAI::Record>s, including an optional resumptionToken string.

=item $token = $lr->resumptionToken([$token])

Returns and optionally sets the L<HTTP::OAI::ResumptionToken|HTTP::OAI::ResumptionToken>.

=item $dom = $lr->toDOM

Returns a XML::DOM object representing the ListRecords response.

=back
