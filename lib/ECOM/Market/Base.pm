package ECOM::Market::Base;

use strict;
use warnings;
use vars qw(@ISA);
use utf8;
no warnings 'utf8';

# ---------------------------------------------------------------
# Telegram bot form ulmart.ru
# Created for http://www.akit.ru/olimpiada/
# Author: Lugovkin Roman, roman.lugovkin@gmail.com
# ---------------------------------------------------------------

use Digest::MD5 qw/md5_hex/;
use HTML::DOM;
use Encode;
use LWP;
use HTTP::Cookies;
use JSON;

my $SESSION_DIR = './sessions';
my $CACHE_DIR = './cache';

sub new {
    my $instance = shift;
    my $class = ref($instance) || $instance;

    my $self = {
        'client_id'     => '',

        'session_dir'   => $SESSION_DIR,
        'cache'         => 0,
        'debug'         => 1,

        @_,

        'ua'            => undef,
        'cookies'       => undef,
        'dom'           => undef,
        'status'        => '',
    };

    bless($self, $class);
    return $self->init;
}

sub init {
    my $self = shift;

    unless ( -d $self->{'session_dir'} ) {
        mkdir $self->{'session_dir'};
    }

    my $session_file = $self->{'session_dir'}.'/'.md5_hex( $self->{'client_id'} ).'.s';
    my $cookie_jar = HTTP::Cookies->new( file => $session_file, autosave => 1, ignore_discard => 1 );

    my $ua = LWP::UserAgent->new;
    $ua->cookie_jar( $cookie_jar );
    push @{ $ua->requests_redirectable }, 'POST';

    $self->{'cookies'} = $cookie_jar;
    $self->{'ua'} = $ua;

    return $self;
}

# -------------------------------------------------------
# Some getters
# -------------------------------------------------------

sub ua {
    my $self = shift;
    return $self->{'ua'};
}

sub status {
    my $self = shift;

    $self->{'status'} = shift @_ if ( @_ );

    return $self->{'status'};
}

# -------------------------------------------------------
# DOM Parsing
# -------------------------------------------------------

sub dom {
    my $self = shift;
    my $url = shift;
    my $post = shift;
    my $headers = shift;

    if ( !$url ) {
        return $self->{'dom'};
    }

    my $html = $self->get_html_page( $url, $post, $headers );
    my $dom = new HTML::DOM;
    $dom->open;
    $dom->write( $html );
    $dom->close;

    $self->{'dom'} = $dom;

    return $dom;
}

sub get_by_class {
    my $self = shift;
    my $class = shift || '';
    my $dom = shift || $self->dom;

    my @elements;

    foreach ( $dom->getElementsByClassName( $class ) ) {
        my $cl = $_->getAttribute('class') || '';
        $cl =~ s/(\r|\n)//gsm;
        $cl =~ s/\s+/ /g;

        my %classes = map { $_ => 1 } split( ' ', $cl );

        if ( exists $classes{$class} ) {
            push @elements, $_;
        }
    }

    return wantarray ? @elements : $elements[0];
}

sub get_item_content {
    my $self = shift;
    my $class = shift;
    my $dom = shift || $self->dom;

    my $content = '';
    if ( $class ) {
        my $element = $self->get_by_class( $class, $dom );
        if ( defined $element ) {
            $content = $element->as_text || '';
        }
    }

    return $content;
}

# -------------------------------------------------------
# Web requests
# -------------------------------------------------------

sub xml_http_request {
    my $self = shift;
    my $url = shift;
    my $headers = shift || [];
    
    push @{$headers}, ( 'X-Requested-With' => 'XMLHttpRequest' );
    
    return $self->get_html_page( $url, undef, $headers );
}

sub get_html_page {
    my $self = shift;
    my $url = shift;
    my $post = shift;
    my $headers = shift || [];

    my $content = '';

    $self->status( '' );
    $self->echo( 'GET PAGE', $url );

    if ( !@{$headers} ) {
        push @{$headers}, ( 'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36' );
    }

    my $r;
    if ( defined $post ) {
        $r = $self->ua->post( $url, $post, @{$headers} );
    }
    else {
        $r = $self->ua->get( $url, @{$headers} );
    }

    if ( $r->is_success ) {
        $self->{'cookies'}->save;
        $content = decode( 'utf8', $r->content );

        if ( $self->{'cache'} ) {
            unless ( -d $self->{'cache'} ) {
                mkdir $self->{'cache'};
            }

            my $cache_file = $self->{'cache'}.'/'.md5_hex( encode( 'utf8', $url ) ).'.html';
            my $fp;

            open $fp, ">$cache_file";
            print $fp qq{<!--$url-->\n};
            print $fp $content;
            close $fp;
        }
    }
    else {
        $self->echo( 'GET PAGE ERROR', $r->status_line );
        $self->status( $r->status_line );
    }

    return $content;
}

# -------------------------------------------------------
# Utility
# -------------------------------------------------------

sub now {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time() );
    $mon ++;
    $year = $year + 1900;

    return sprintf("%02d.%02d.%04d %02d:%02d:%02d", $mday, $mon, $year, $hour, $min, $sec);
}

sub echo {
    my $self = shift;

    if ( $self->{'debug'} ) {
        my $msg = join( "\t", $self->now, @_ );
        print $msg, "\n";
    }

    return $self;
}

1;