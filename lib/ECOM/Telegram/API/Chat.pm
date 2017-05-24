package ECOM::Telegram::API::Chat;

use strict;
use warnings;
use vars qw(@ISA);
use utf8;
use Encode;
use JSON;
use Storable qw/retrieve nstore/;
use Digest::MD5 qw/md5_hex/;

# ---------------------------------------------------------------
# Telegram bot form ulmart.ru
# Created for http://www.akit.ru/olimpiada/
# Author: Lugovkin Roman, roman.lugovkin@gmail.com
# ---------------------------------------------------------------

use ECOM::Market::Ulmart;

my $SESSION_DIR = './sessions';
my $SESSION_DATA = {
    'last_info'     => {},
    'last_catalog'  => '/catalog',
    'csrf'          => '',
    'state'         => '',
    'state_data'    => '',
};

sub new {
    my $instance = shift;
    my $class = ref($instance) || $instance;

    my $self = {
        'chat'          => {},
        'session_dir'   => $SESSION_DIR,
        @_,
        'data_file'     => '',
        'data'          => $SESSION_DATA,
        'market'        => undef,
    };

    bless($self, $class);
    return $self->init;
}

sub init {
    my $self = shift;

    unless ( -d $self->{'session_dir'} ) {
        mkdir $self->{'session_dir'};
    }

    # Session connect to the market web site
    $self->{'market'} = ECOM::Market::Ulmart->new( 'client_id' => $self->chat_id );

    # Loading session state from file storage
    my $session_file = $self->{'session_dir'}.'/'.md5_hex( $self->chat_id ).'.dat';
    $self->{'data_file'} = $session_file;
    if ( -e $session_file ) {
        $self->{'data'} = retrieve $session_file;
    }

    return $self;
}

sub chat_id {
    my $self = shift;
    return $self->{'chat'}->{'id'};
}

sub market {
    my $self = shift;
    return $self->{'market'};
}

sub data {
    my $self = shift;
    return $self->{'data'};
}

sub csrf {
    my $self = shift;
    my $data_ref = $self->data;
    if ( @_ ) {
        $data_ref->{'csrf'} = shift @_;
        $self->store;
    }
    return $data_ref->{'csrf'};
}

sub store {
    my $self = shift;

    nstore $self->{'data'}, $self->{'data_file'};

    return $self;
}

# ------------------------------------------------
# Flags state management
# ------------------------------------------------

sub state {
    my $self = shift;
    my $cmd = shift || '';
    my $data = shift || '';
    
    my $data_ref = $self->data;
    if ( $cmd ) {
        $data_ref->{'state'} = $cmd;
        $data_ref->{'state_data'} = $data;
        $self->store;
    }
    
    return ( $data_ref->{'state'} || '', $data_ref->{'state_data'}  || '' );
}

sub reset_state {
    my $self = shift;

    my $data_ref = $self->data;
    $data_ref->{'state'} = '';
    $data_ref->{'state_data'} = '';
    $self->store;

    return $self;
}

# ------------------------------------------------
# Get info
# ------------------------------------------------

sub store_last_info {
    my $self = shift;
    my $ref = shift || {};

    my $data_ref = $self->data;
    if ( $ref->{'info'} ) {
        $data_ref->{'last_info'} = $ref->{'info'};
        $self->store;
    }

    return $data_ref;
}

# ------------------------------------------------
# Get status info
# ------------------------------------------------

sub get_info {
    my $self = shift;

    my $catalog = $self->market->get_catalog;
    $self->store_last_info( $catalog );
    
    return $catalog->{'info'};
}

# ------------------------------------------------
# Get catalog
# ------------------------------------------------

sub get_catalog {
    my $self = shift;
    my $part = shift || '/catalog';
    my $page = shift || 0;

    my $catalog = $self->market->get_catalog( $part, $page );
    $self->store_last_info( $catalog );

    return $catalog;
}

sub search {
    my $self = shift;
    my $query = shift || '';
    my $page = shift || 0;

    my $search = $self->market->search( $query, $page );
    $self->store_last_info( $search );

    return $search;
}

sub checkout {
    my $self = shift;
    my $shop_id = shift || 0;
    my $csrf = shift || '';

    my $checkout = $self->market->checkout( $shop_id, $csrf );
    $self->store_last_info( $checkout );

    return $checkout;
}

sub confirm {
    my $self = shift;
    my $shop_id = shift || 0;
    my $csrf = shift || '';

    my $confirm = $self->market->confirm( $shop_id, $csrf );

    return $confirm;
}

# ------------------------------------------------
# Get item
# ------------------------------------------------

sub get_item {
    my $self = shift;
    my $part = shift || '';

    my $item = $self->market->get_item( $part );
    $self->store_last_info( $item );

    return $item;
}

# ------------------------------------------------
# City management
# ------------------------------------------------

sub get_city {
    my $self = shift;
    my $city_id = shift;
    my $csrf = shift;
    
    if ( $city_id ) {
        return $self->market->get_city_list( $city_id, $csrf );
    }
    
    return $self->market->get_state_city_list;
}

sub set_city {
    my $self = shift;
    my $city_id = shift;
    my $csrf = shift;

    my $info = $self->market->set_city( $city_id, $csrf );
    $self->store_last_info( $info );

    return $info;    
}

# ------------------------------------------------
# Shopping cart manipulations
# ------------------------------------------------

sub add_to_cart {
    my $self = shift;
    my $goods_id = shift || '';

    my $cart = $self->market->add_to_cart( $goods_id );
    $self->store_last_info( $cart );

    return $cart;
}

sub get_cart {
    my $self = shift;

    my $cart = $self->market->get_cart;
    $self->store_last_info( $cart );

    return $cart;
}

sub inc_in_cart {
    my $self = shift;
    my $goods_id = shift || '';

    my $cart = $self->market->inc_in_cart( $goods_id );
    $self->store_last_info( $cart );

    return $cart;
}

sub dec_in_cart {
    my $self = shift;
    my $goods_id = shift || '';

    my $cart = $self->market->dec_in_cart( $goods_id );
    $self->store_last_info( $cart );

    return $cart;
}

sub del_from_cart {
    my $self = shift;
    my $goods_id = shift || '';

    my $cart = $self->market->del_from_cart( $goods_id );
    $self->store_last_info( $cart );

    return $cart;
}

sub clear_cart {
    my $self = shift;
    my $goods_id = shift || '';

    my $cart = $self->market->clear_cart;
    $self->store_last_info( $cart );

    return $cart;
}

1;