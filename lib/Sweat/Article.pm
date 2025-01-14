package Sweat::Article;

use warnings;
use strict;
use Moo;
use namespace::clean;
use utf8::all;

use Types::Standard qw( Str Maybe );

use Scalar::Util qw( blessed );
use HTML::Strip;
use List::Util qw( shuffle );
use MediaWiki::API;

has 'text' => (
    is => 'ro',
    required => 1,
    isa => Str,
);

has 'title' => (
    is => 'ro',
    required => 1,
    isa => Str,
);

has 'url' => (
    is => 'ro',
    required => 1,
);

our $stripper = HTML::Strip->new;
our $mw = MediaWiki::API->new;

$mw->{config}->{max_lag} = 2;
$mw->{config}->{max_lag_delay} = 1;
our $language;

our %seen_titles;

sub new_from_newsapi_article {
    my ( $class, $newsapi_article ) = @_;

    die "Expected a NewsAPI article, got $newsapi_article"
        unless blessed($newsapi_article)
               && $newsapi_article->isa( 'Web::NewsAPI::Article' );

    my $sweat_article = $class->new(
        text => ($newsapi_article->title // q{})
                . q{. }
                . ($newsapi_article->description // q{}),
        url => $newsapi_article->url,
        title => $newsapi_article->title,
    );

    return $sweat_article;
}

sub new_from_random_wikipedia_article {
    my ($class) = @_;

    my $title = _get_random_title();
    return $class->new_from_wikipedia_title($title);
}

sub new_from_linked_wikipedia_article {
    my ($class, $article) = @_;

    my $title = _get_random_title_linked_from_title($article->title);
    return $class->new_from_wikipedia_title($title);
}

sub new_from_wikipedia_title {
    my ($class, $title) = @_;

    my $summary = _get_summary_for_title($title);
    my $tries = 0;
    until ($summary || ($tries >= 3) ) {
        $tries++;
        $title = _get_random_title_linked_from_title($title);
        $summary = _get_summary_for_title($title);
    }
    unless ( $summary ) {
        $title = _get_random_title();
        $summary = _get_summary_for_title($title);
    }

    return $class->new(
        title => $title,
        text => $summary,
        url => "https://$language.wikipedia.org/wiki/$title",
    );
}

sub _get_random_title {
    my $result = $mw->api( {
        list => 'random',
        action => 'query',
        rnnamespace => 0,
    } );

    return $result->{query}->{random}->[0]->{title};
}

sub _get_summary_for_title {
    my ($title) = @_;

    my $result = $mw->api( {
        action => 'query',
        prop => 'extracts',
        exintro => undef,
        titles => $title,
    } );

    my $summary = (values(%{$result->{query}->{pages}}))[0]->{extract};

    if (defined $summary) {
        $summary = $stripper->parse( $summary );
        # Eliminate all parentheticals (birth/death dates, alternate-language
        # representations, and so on) because they don't read out loud well.
        my $found_some;
        until ( defined($found_some) && not($found_some) ) {
            $found_some = $summary =~ s/\([^\(]*?\)//g;
        }
        # Clean up redundant whitespace, and whitespace before punctuation.
        $summary =~ s/\s+([,.!?;:])/$1/g;
        $summary =~ s/ {2,}/ /g;
    }
    if ( $summary && $summary =~ /\S/ ) {
        return $summary;
    }
    else {
        return undef;
    }
}

sub _erase_parentheticals {
    my ( $summary, $opener, $closer ) = @_;
    my $found_some;
    until ( defined($found_some) && not($found_some) ) {
        $found_some = $summary =~ s/\([^\(]*?\)//g;
        warn "Found some: $found_some\n";
    }
    return $summary;
}


sub _get_random_title_linked_from_title {
    my ($title) = @_;

    my $result = $mw->api( {
        action => 'query',
        prop => 'links',
        titles => $title,
        plnamespace => 0,
        pllimit => 100,
    } );

    my $links_ref = (values(%{$result->{query}->{pages}}))[0]->{links};

    my @links = shuffle(@$links_ref);

    my $linked_title;

    until ($linked_title || (@links == 0 )) {
        if (defined $links[0]) {
            my $proposed_title = $links[0]->{title};
            # Skip:
            # * Any title we've already seen
            # * Any title with a numeral in it (to stay away from annual-
            #   statistics gravity wells)
            # * Any title with a word suggesting it's a just a list or table
            unless (
                $seen_titles{$proposed_title}
                ||
                $proposed_title =~ /\d|^list of\s|^comparison of\s|^table of\s/i
            ) {
                $linked_title = $proposed_title;
                $seen_titles{$proposed_title} = 1;
            }
        }
        shift @links;
    }

    if ($linked_title) {
        return $linked_title;
    }
    else {
        return _get_random_title();
    }
}


1;

=head1 Sweat::Article - Library for the `sweat` command-line program

=head1 DESCRIPTION

This library is intended for internal use by the L<sweat> command-line program,
and as such offers no publicly documented methods.

=head1 SEE ALSO

L<sweat>

=head1 AUTHOR

Jason McIntosh <jmac@jmac.org>
