package HTTP::OAI::Metadata::METS;

use strict;
use warnings;

use HTTP::OAI::Metadata;
use vars qw(@ISA);
@ISA = qw(HTTP::OAI::Metadata);

use XML::LibXML;
use XML::LibXML::XPathContext;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	my %args = @_;
	$self;
}

sub _xc
{
	my $xc = XML::LibXML::XPathContext->new( @_ );
	$xc->registerNs( 'mets', 'http://www.loc.gov/METS/' );
	$xc->registerNs( 'xlink', 'http://www.w3.org/1999/xlink' );
	return $xc;
}

sub files
{
	my $self = shift;
	my $dom = $self->dom;

	my $xc = _xc($dom);

	my @files;
	foreach my $file ($xc->findnodes( '//mets:file' ))
	{
		my $f = {};
		foreach my $attr ($file->attributes)
		{
			$f->{ $attr->nodeName } = $attr->nodeValue;
		}
		$file = _xc($file);
		foreach my $locat ($file->findnodes( 'mets:FLocat' ))
		{
			$f->{ url } = $locat->getAttribute( 'xlink:href' );
		}
		push @files, $f;
	}

	return @files;
}

1;

__END__

=head1 NAME

HTTP::OAI::Metadata::METS - METS accessor utility

=head1 DESCRIPTION

=head1 SYNOPSIS

=head1 NOTE
