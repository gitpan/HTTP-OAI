package HTTP::OAI::Encapsulation;

use strict;
use Carp;

use HTTP::OAI::SAXHandler qw( :SAX );
use XML::LibXML::SAX;
use XML::LibXML::SAX::Builder;
use XML::LibXML::SAX::Parser;

use vars qw(@ISA);

@ISA = qw(XML::SAX::Base);

sub new {
	my $class = shift;
	my %args = @_ > 1 ? @_ : (dom => shift);
	my $self = bless {}, ref($class) || $class;
	$self->version($args{version});
	$self->dom($args{dom});
	$self;
}

sub dom { shift->_elem('dom',@_) }

# Pseudo HTTP::Response
sub code { 200 }
sub message { 'OK' }

sub is_info { 0 }
sub is_success { 1 }
sub is_redirect { 0 }
sub is_error { 0 }

sub version { shift->_elem('version',@_) }

sub _elem {
	my $self = shift;
	my $name = shift;
	return @_ ? $self->{_elem}->{$name} = shift : $self->{_elem}->{$name};
}

sub _attr {
	my $self = shift;
	my $name = shift or return $self->{_attr};
	return $self->{_attr}->{$name} unless @_;
	if( defined(my $value = shift) ) {
		return $self->{_attr}->{$name} = $value;
	} else {
		delete $self->{_attr}->{$name};
		return undef;
	}
}

package HTTP::OAI::Encapsulation::DOM;

use Carp;

use vars qw(@ISA);
@ISA = qw(HTTP::OAI::Encapsulation);

sub toString { defined($_[0]->dom) ? $_[0]->dom->toString : undef }

sub generate {
	my $self = shift;
	carp("Empty Metadata object (use ".ref($self)."->dom() to specify a DOM object)")
		unless defined($self->dom);
	return unless defined($self->dom) and defined($self->get_handler);
	my $driver = XML::LibXML::SAX::Parser->new(
			Handler=>HTTP::OAI::FilterDOMFragment->new(
				Handler=>$self->get_handler
	));
	$driver->generate($self->dom->ownerDocument);
}

sub start_document {
	my ($self) = @_;
	my $builder = XML::LibXML::SAX::Builder->new() or die "Unable to create XML::LibXML::SAX::Builder: $!";
	$self->{OLDHandler} = $self->get_handler();
	$self->set_handler($builder);
	$self->SUPER::start_document();
	$self->SUPER::xml_decl({'Version'=>'1.0','Encoding'=>'UTF-8'});
}

sub end_document {
	my ($self) = @_;
	$self->SUPER::end_document();
	$self->dom($self->get_handler->result());
	$self->set_handler($self->{OLDHandler});
}

package HTTP::OAI::Metadata;

use vars qw(@ISA);
@ISA = qw(HTTP::OAI::Encapsulation::DOM);

1;

__END__

=head1 NAME

HTTP::OAI::Metadata - Base class for data objects that contain DOM trees

=head1 SYNOPSIS

	use HTTP::OAI::Metadata;

	$md = new HTTP::OAI::Metadata(dom=>$xml);

	print $md->dom->toString;

	my $dom = $md->dom(); # Return internal DOM tree
