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
	$self->verb('ListRecords') unless $self->verb;

	$self;
}

sub resumptionToken { shift->headers->header('resumptionToken',@_) }

sub record {
	my $self = shift;
	push(@{$self->{record}}, @_);
	return wantarray ?
		@{$self->{record}} :
		$self->{record}->[0];
}

sub next {
	my $self = shift;
	my $value = shift @{$self->{record}};
	return $value if $value;
	return undef if (!$self->{'resume'} || !$self->resumptionToken || $self->resumptionToken->is_empty);

	my $r = $self->resume(resumptionToken=>$self->resumptionToken);
	return $r->is_success ? $self->next : $r;
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
	my $elem = lc($hash->{Name});
	if( $elem eq 'header' ) {
		if( !$self->{"in_$elem"} || $self->{"in_$elem"} == $hash->{Depth} ) {
			$self->record(my $header = new HTTP::OAI::Record(
					version=>$self->version,
					handlers=>$self->{handlers},
				));
			$self->set_handler($header);
			$self->{"in_$elem"} = $hash->{Depth};
		}
	} elsif( $elem eq 'resumptiontoken' ) {
		$self->resumptionToken(my $rt = new HTTP::OAI::ResumptionToken(version=>$self->version));
		$self->set_handler($rt);
	}
	$self->SUPER::start_element($hash);
}

1;

__END__

=head1 NAME

HTTP::OAI::ListRecords - Provide access to an OAI ListRecords response

=head1 SYNOPSIS

	my $r = $h->ListRecords(-metadataPrefix=>'oai_dc');

	die $r->message if $r->is_error;

	while( my $rec = $r->next ) {
		die $rec->message if $rec->is_error;
		print "Identifier => ", $rec->identifier, "\n";
	}

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
