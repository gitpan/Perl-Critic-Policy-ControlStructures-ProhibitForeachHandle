package Perl::Critic::Policy::ControlStructures::ProhibitForeachHandle;

use 5.006001;

use strict;
use warnings;

use base qw{ Perl::Critic::Policy };

use Perl::Critic::Document;
use Perl::Critic::Utils qw< hashify :severities >;
use Readonly;

our $VERSION = '0.000_01';

#-----------------------------------------------------------------------------

Readonly::Scalar my $DESC =>
    q{You should not use '%s' to iterate over a file};
Readonly::Scalar my $EXPL =>
    q{Using 'while (<handle>)' only reads one line at a time};

sub default_severity    { return $SEVERITY_MEDIUM       }
sub default_themes      { return qw< trw >              }
sub applies_to          { return qw< PPI::Statement >   }

Readonly::Hash   my %FOREACH        => hashify( qw< for foreach > );
Readonly::Scalar my $GREATER_THAN   => '>';
Readonly::Scalar my $LESS_THAN      => '<';

#-----------------------------------------------------------------------------

sub violates {
    my ( $self, $elem ) = @_;

    # We have to compute our starting point based on the actual class of
    # $elem, but we need to verify that it is a word, and that its
    # contents are 'for' or 'foreach'.
    my $start = $self->_find_starting_point( $elem )
        or return;
    $start->isa( 'PPI::Token::Word' )
        or return;
    $FOREACH{ $start->content() }
        or return;

    # We need to look at the next sibling, but if it's 'my' we need to
    # skip over it and the symbol being defined.
    my $item = $start->snext_sibling()
        or return;
    if ( $item->isa( 'PPI::Token::Word' )
        && 'my' eq $item->content()
    ) {
        $item = $item->snext_sibling()
            or return;
        $item->isa( 'PPI::Token::Symbol' )
            or return;
        $item = $item->snext_sibling()
            or return;
    }

    # We ought now to be on the item of interest. Figure out what the
    # offenders contained in it are.
    my @offender = $self->_list_offenders( $item );

    # Map the offenders into violation objects, and return them.
    return ( map {
        $self->violation( sprintf( $DESC, $start->content() ), $EXPL, $_ ) 
        } @offender );
}

#-----------------------------------------------------------------------------

# The actual analysis is easier if we go right to left. But that means
# we may have to back up through the expression to find our starting
# point. The argument is the PPI::Statement object under analysis. The
# return is one of its children, or nothing. If something is returned,
# the caller needs to make sure it is a word and has the desired
# content.
sub _find_starting_point {
    my ( undef, $elem ) = @_;   # Invocant not used.

    # Compound statements are the easiest. We just return the first
    # significant child, if any.
    $elem->isa( 'PPI::Statement::Compound' )
        and return $elem->schild( 0 );

    # If we're not a plain statement, we return nothing.
    'PPI::Statement' eq ref $elem
        or return;

    # For plain statements, we start our scan at the last element. If
    # there is none, we return.
    my $start = $elem->schild( -1 )
        or return;

    # If we got the terminating semicolon we back up one, returning if
    # we run off the left-hand end of the statement.
    if ( $start->isa( 'PPI::Token::Structure' ) ) {
        $start = $start->sprevious_sibling()
            or return;
    }

    # If we got a list or a readline, we return whatever is before it.
    if ( $start->isa( 'PPI::Structure::List' )
        || $start->isa( 'PPI::Token::QuoteLike::Readline' ) ) {
        return $start->sprevious_sibling();
    }

    # If we got the greater-than operator, we are probably looking at a
    # PPI mis-parse of the readline operator.
    if ( $start->isa( 'PPI::Token::Operator' )
        && $GREATER_THAN eq $start->content()
    ) {

        # Back up one. If nothing there, we can't be a mis-parsed
        # readline.
        $start = $start->sprevious_sibling()
            or return;

        # If we got a word or a symbol, we still may be a mis-parse.
        # Back up another, or return if we can't.
        if ( $start->isa( 'PPI::Token::Word' )
            || $start->isa( 'PPI::Token::Symbol' )
        ) {
            $start = $start->sprevious_sibling()
                or return;
        }

        # If we're at a less-than operator, this looks mighty like PPI
        # mis-parsed a readline operator. Accept it as such and return
        # the previous element, whatever it is.
        $start->isa( 'PPI::Token::Operator' )
            and $LESS_THAN eq $start->content()
            and return $start->sprevious_sibling();

        # We didn't recognize a mis-parsed readline. Just return.
        return;
    }

    # No telling what we have at this point. Just return.
    return;

}

#-----------------------------------------------------------------------------

# Retirm any offending elements starting at the given element. If the
# element is a node you get its offending contents. Otherwise you get
# the element itself if it offends, or nothing if it's OK.
sub _list_offenders {
    my ( $self, $elem ) = @_;

    # If we have a node, the return is all the offenders it contains (if
    # any).
    $elem->isa( 'PPI::Node' )
        and return (
        map { $self->_list_offenders( $_ ) } $elem->schildren()
    );

    # If we have a readline, it may or may not be offensive. The problem
    # is that PPI does not distinguish very well between readlines and
    # file globs.
    if ( $elem->isa( 'PPI::Token::QuoteLike::Readline' ) ) {
        my $content = $elem->content();
        # If it doesn't look like a word or a scalar in angle brackets,
        # it is probably actually a file glob operator.
        $content =~ m/ \A < (?: \$ )? \w* > \z /smx
            or return;
        return $elem;
    }

    # If we have the less-than operator it might be the start of a
    # mis-parsed readline operator. Check it out.
    if ( $elem->isa( 'PPI::Token::Operator' )
        && $LESS_THAN eq $elem->content()
    ) {

        # If it's a mis-parse, there has to be more there.
        my $next = $elem->snext_sibling()
            or return;

        # If we found a word or a symbol, there has to be more yet.
        if ( $next->isa( 'PPI::Token::Word' )
            || $next->isa( 'PPI::Token::Symbol' )
        ) {
            $next = $next->snext_sibling()
                or return;
        }

        # If we hit a greater-than operator, the original less-than
        # operator is offensive.
        $next->isa( 'PPI::Token::Operator' )
            and $GREATER_THAN eq $next->content()
            and return $elem;

        # Anything else is benign.
        return;
    }

    # Everything else is benign.
    return;
}

1;

__END__

=head1 NAME

Perl::Critic::Policy::ControlStructures::ProhibitForeachHandle - Don't use C<foreach> to iterate over a file handle.


=head1 AFFILIATION

This Policy is stand-alone, and is not part of the core
L<Perl::Critic|Perl::Critic>.

=head1 DESCRIPTION

The problem with using

    foreach ( <$handle> ) { ... }

to iterate over the lines in a file is that it reads the entire file
into memory before the iteration even starts, with the consequent impact
on the memory footprint of the script. Almost always, what you wanted
instead was

    while ( <$handle> ) { ... }

which reads the lines of the file one at a time.

The insidious thing is that C<< foreach ( <$handle> ) >> actually
produces a working script. So unless the script actually runs out of
memory or pages itself to death the potantial problem goes unnoticed.

Hence this policy.

=head1 CONFIGURATION

This policy supports no configuration items other than the standard
ones.

=head1 SUPPORT

Support is by the author. Please file bug reports at
L<http://rt.cpan.org>, or in electronic mail to the author.

=head1 AUTHOR

Thomas R. Wyant, III F<wyant at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 72
#   indent-tabs-mode: nil
#   c-indentation-style: bsd
# End:
# ex: set ts=8 sts=4 sw=4 tw=72 ft=perl expandtab shiftround :
