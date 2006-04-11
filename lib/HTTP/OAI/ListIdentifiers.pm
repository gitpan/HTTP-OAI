package HTTP::OAI::ListIdentifiers;

use HTTP::OAI::Header;
use HTTP::OAI::ResumptionToken;

use HTTP::OAI::Response;

use vars qw( @ISA );
@ISA = qw( HTTP::OAI::Response );

sub new {
	my $class = shift;
	my %args = @_;
	
	my $self = $class->SUPER::new(@_);

	$self->{identifier} ||= [];
	$self->{onRecord} = $args{onRecord};

	$self;
}

sub resumptionToken { shift->headers->header('resumptionToken',@_) }

sub identifier {
	my $self = shift;
	return $self->{onRecord}->($_[0]) if @_ and defined($self->{onRecord});
	push(@{$self->{identifier}}, @_);
	return wantarray ?
		@{$self->{identifier}} :
		$self->{identifier}->[0];
}

sub next {
	my $self = shift;
	return shift @{$self->{identifier}} if @{$self->{identifier}};
	return undef if (!$self->{'resume'} || !$self->resumptionToken || $self->resumptionToken->is_empty);

	$self->resume(resumptionToken=>$self->resumptionToken);
	return $self->is_success ? $self->next : undef;
}

sub generate_body {
	my ($self) = @_;
	return unless defined(my $handler = $self->get_handler);

	for($self->identifier) {
		$_->set_handler($handler);
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
	if( $elem eq 'header' ) {
		my $header = new HTTP::OAI::Header(version=>$self->version);
		$self->set_handler($header);
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
	if( $elem eq 'header' ) {
		$self->identifier( $self->get_handler );
		$self->set_handler( undef );
	}
	# OAI 1.x
	if( $self->version eq '1.1' && $elem eq 'identifier' ) {
		$self->identifier(new HTTP::OAI::Header(
			version=>$self->version,
			identifier=>$hash->{Text},
			datestamp=>'0000-00-00',
		));
	}
}

1;

__END__

=head1 NAME

OAI::ListIdentifiers - Provide access to an OAI ListIdentifiers response

=head1 SYNOPSIS

	my $r = $h->ListIdentifiers;

	while(my $rec = $r->next) {
		print "identifier => ", $rec->identifier, "\n",
		print "datestamp => ", $rec->datestamp, "\n" if $rec->datestamp;
		print "status => ", ($rec->status || 'undef'), "\n";
	}
	
	die $r->message if $r->is_error;

=head1 METHODS

=over 4

=item $li = new OAI::ListIdentifiers

This constructor method returns a new OAI::ListIdentifiers object.

=item $rec = $li->next

Returns either an L<HTTP::OAI::Header|HTTP::OAI::Header> object, or undef, if there are no more records. Use $rec->is_error to test whether there was an error getting the next record (otherwise things will break).

If -resume was set to false in the Harvest Agent, next may return a string (the resumptionToken).

=item @il = $li->identifier([$idobj])

Returns the identifier list and optionally adds an identifier or resumptionToken, $idobj. Returns an array ref of L<HTTP::OAI::Header|HTTP::OAI::Header>s.

=item $dom = $li->toDOM

Returns a XML::DOM object representing the ListIdentifiers response.

=item $token = $li->resumptionToken([$token])

Returns and optionally sets the L<HTTP::OAI::ResumptionToken|HTTP::OAI::ResumptionToken>.

=back
