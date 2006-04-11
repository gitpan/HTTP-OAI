package HTTP::OAI::ListSets;

use HTTP::OAI::Set;
use HTTP::OAI::ResumptionToken;

use HTTP::OAI::Response;

use vars qw( @ISA );
@ISA = qw( HTTP::OAI::Response );

sub new {
	my ($class,%args) = @_;
	
	$args{handlers} ||= {};
	$args{handlers}->{description} ||= 'HTTP::OAI::Metadata';
	
	my $self = $class->SUPER::new(%args);
	
	$self->{set} ||= [];
	$self->{onRecord} = $args{onRecord};

	$self;
}

sub resumptionToken { shift->headers->header('resumptionToken',@_) }

sub set {
	my $self = shift;
	return $self->{onRecord}->($_[0]) if @_ and defined($self->{onRecord});
	push(@{$self->{set}}, @_);
	return wantarray ?
		@{$self->{set}} :
		$self->{set}->[0];
}

sub next {
	my $self = shift;
	return shift @{$self->{set}} if @{$self->{set}};
	return undef if (!$self->{'resume'} || !$self->resumptionToken || $self->resumptionToken->is_empty);

	$self->resume(resumptionToken=>$self->resumptionToken);
	return $self->is_success ? $self->next : undef;
}

sub generate_body {
	my ($self) = @_;
	return unless defined(my $handler = $self->get_handler);

	for( $self->set ) {
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
	my $elem = lc($hash->{Name});
	if( $elem eq 'set' ) {
		if( !$self->{in_set} ) {
			$self->set_handler(new HTTP::OAI::Set(
				version=>$self->version,
				handlers=>$self->{handlers}
			));
			$self->{in_set} = $hash->{Depth};
		}
	} elsif( $elem eq 'resumptiontoken' ) {
		$self->resumptionToken(my $rt = new HTTP::OAI::ResumptionToken(version=>$self->version));
		$self->set_handler($rt);
	}
	$self->SUPER::start_element($hash);
}

sub end_element {
	my ($self,$hash) = @_;
	$self->SUPER::end_element($hash);
	if( lc($hash->{Name}) eq 'set' and $self->{in_set} == $hash->{Depth} ) {
		$self->set( $self->get_handler );
		$self->set_handler( undef );
		$self->{in_set} = 0;
	}
}

1;

__END__

=head1 NAME

HTTP::OAI::ListSets - Provide access to an OAI ListSets response

=head1 SYNOPSIS

	my $r = $h->ListSets();

	while( my $rec = $r->next ) {
		print $rec->setSpec, "\n";
	}

	die $r->message if $r->is_error;

=head1 METHODS

=over 4

=item $ls = new HTTP::OAI::ListSets

This constructor method returns a new OAI::ListSets object.

=item $set = $ls->next

Returns either an L<HTTP::OAI::Set|HTTP::OAI::Set> object, or undef, if no more records are available. Use $set->is_error to test whether there was an error getting the next record.

If -resume was set to false in the Harvest Agent, next may return a string (the resumptionToken).

=item @setl = $ls->set([$set])

Returns the set list and optionally adds a new set or resumptionToken, $set. Returns an array ref of L<HTTP::OAI::Set|HTTP::OAI::Set>s, with an optional resumptionToken string.

=item $token = $ls->resumptionToken([$token])

Returns and optionally sets the L<HTTP::OAI::ResumptionToken|HTTP::OAI::ResumptionToken>.

=item $dom = $ls->toDOM

Returns a XML::DOM object representing the ListSets response.

=back
