package ECOM::Market::Ulmart;

use strict;
use warnings;
use vars qw(@ISA);
use utf8;

# ---------------------------------------------------------------
# Telegram bot form ulmart.ru
# Created for http://www.akit.ru/olimpiada/
# Author: Lugovkin Roman, roman.lugovkin@gmail.com
# ---------------------------------------------------------------

use ECOM::Market::Base;
use parent 'ECOM::Market::Base';

my $DOMAIN = 'http://m.ulmart.ru';

sub init {
    my $self = shift;

    $self->SUPER::init( @_ );

    return $self;
}

# ----------------------------------------------
# Objects struct defenitions
# ----------------------------------------------

my $CATALOG_ITEM = {
    'href'  => '',
    'title' => '',
};

my $PRODUCT_ITEM = {
    'goods_id'          => '',
    'href'              => '',
    'back'              => '',
    'title'             => '',
    'img'               => '',
    'cost'              => '',
    'cost_old'          => '',
    'in_cart'           => 0,
    'rating'            => 0,
    'rating_counter'    => 0,
    'in_stock'          => 0,
    'text'              => '',
    'description'       => [],
    'images'            => [],
    'info'              => {},
};

my $CATALOG_PAGE = {
    'info'          => {},
    'url'           => '',
    'back'          => '',
    'title'         => '',
    'counter'       => '',
    'pages'         => '',
    'active_page'   => '',
    'filter'        => '',
    'items'         => [],
    'products'      => [],
};

# ----------------------------------------------------------------
# $info = get_info()
# ----------------------------------------------------------------
# Parsing cart and city info for loaded page
# ----------------------------------------------------------------

sub get_info {
    my $self = shift;

    my $info = {
        'cart_cost'     => as_number( $self->get_item_content( 'b-basket-info__cost' ) ),
        'cart_counter'  => as_number( $self->get_item_content( 'b-basket-info__counter' ) ),
        'city'          => '',
        'csrf'          => $self->csrf,
    };

    foreach ( $self->get_by_class( 'b-swipe-menu-links__item' ) ) {
        my $href = $_->getAttribute('href') || '';
        if ( $href eq '/listCities' ) {
            $info->{'city'} = $_->as_text || '';
            last;
        }
    }

    return $info;
}

# ----------------------------------------------------------------
# $products = get_products()
# ----------------------------------------------------------------
# Parsing products list for loaded page
# ----------------------------------------------------------------

sub get_products {
    my $self = shift;

    # Parsing products list
    my @products;
    foreach my $item ( $self->get_by_class( 'b-what-looked__item' ) ) {
        my $product = {
            %{$PRODUCT_ITEM},
            'goods_id'          => $self->get_by_class( 'js-gtm-product-click', $item )->getAttribute('data-gtm-eventproductid') || '',,
            'href'              => $self->get_by_class( 'js-gtm-product-click', $item )->getAttribute('href') || '',
            'title'             => as_clear( $self->get_item_content( 'b-what-looked-product__name', $item ) ),
            'img'               => $self->get_by_class( 'b-what-looked-product__img', $item )->getAttribute('src') || '',
            'cost'              => as_number( $self->get_item_content( 'b-what-looked-product__cost', $item ) ),
            'cost_old'          => as_number( $self->get_item_content( 'b-what-looked-product__cost_old', $item ) ),
            'rating_counter'    => as_number( $self->get_item_content( 'b-rating__counter', $item ) ),
            'rating'            => 0,
            'in_stock'          => 0,
            'description'       => [],
            'images'            => [],
            'info'              => {},
        };

        my @rating = $self->get_by_class( 'b-rating__item_state-active', $item );
        $product->{'rating'} = scalar( @rating );

        my @ico = $self->get_by_class( 'b-ico_basket-white', $item );
        if ( scalar( @ico ) ) {
            $product->{'in_stock'} = 1;
            my $top_a = $ico[0]->parentNode;
            if ( $top_a ) {
                my $href = $top_a->getAttribute('href') || '';
                if ( $href eq '/cart' ) {
                    $product->{'in_cart'} = 1;
                }
            }

        }

        push @products, $product;
    }

    # Parsing paginator line
    my @numbers = $self->get_by_class( 'b-paginator__number' );
    my $active_page = as_number( $self->get_item_content( 'b-paginator__item_active' ) );
    my $last_page = 0;
    if ( @numbers ) {
        $last_page = as_number( $numbers[-1]->as_text );
    }

    # Check filter btn
    my $filter = '';
    my @flt = $self->get_by_class( 'b-ico_filter' );
    if ( @flt ) {
        my $top_a = $flt[0]->parentNode;
        if ( $top_a ) {
            $filter = $top_a->getAttribute('href') || '';
        }
    }
    else {
        foreach ( $self->get_by_class( 'b-menu-text' ) ) {
            my $href = $_->getAttribute('href') || '';
            if ( $href =~ /\/filter/ ) {
                $filter = $href;
                last;
            }
        }
    }

    # Check back btn
    my $back = '';
    my @bk = $self->get_by_class( 'b-ico_back' );
    if ( @bk ) {
        my $top_a = $bk[0]->parentNode;
        if ( $top_a ) {
            $back = $top_a->getAttribute('href') || '';
        }
    }
    else {
        foreach ( $self->get_by_class( 'b-mobile-menu' ) ) {
            my $href = $_->getAttribute('href') || '';
            if ( $href =~ /^\/catalog/ ) {
                $back = $href;
                last;
            }
        }
    }

    return {
        'pages'         => $last_page,
        'active_page'   => $active_page,
        'filter'        => $filter,
        'back'          => $back,
        'products'      => \@products,
    };
}

# ----------------------------------------------------------------
# $catalog = get_catalog( $catalog_root )
# ----------------------------------------------------------------
# List catalog level items or products list from $catalog_root
# $catalog_root = '/catalog' or '' as root
# $catalog - structure of $CATALOG_PAGE type
# ----------------------------------------------------------------

sub get_catalog {
    my $self = shift;
    my $root = shift || '/catalog';
    my $page_num = shift || '';

    my @items;

    my $url = $DOMAIN.$root;
    if ( $page_num ) {
        $url .= '?' unless ( $url =~ /\?/ );
        $url .= qq{&pageNum=$page_num};
    }
    my $dom = $self->dom( $url );

    my $info = $self->get_info;
    my $title = $self->get_item_content( 'b-catalogue__header-text' );
    my $counter = as_number( $self->get_item_content( 'b-catalogue__header-counter' ) );

    # Parsing catalog items
    foreach my $item ( $self->get_by_class( 'b-catalogue-list__item' ) ) {
        my $href = $item->getAttribute('href') || '';
        my $title = $item->getAttribute('data-gtm-eventcontent') || '';
        if ( $href and $title ) {
            push @items, {
                %{$CATALOG_ITEM},
                'href'  => $href,
                'title' => $title
            };
        }
    }

    my $products_on_page = $self->get_products;

    return {
        %{$CATALOG_PAGE},
        'info'          => $info,
        'url'           => $root,
        'title'         => $title,
        'counter'       => $counter,
        'items'         => \@items,
        %{$products_on_page}
    };
}

# ----------------------------------------------------------------
# $catalog = search( $query )
# ----------------------------------------------------------------

sub search {
    my $self = shift;
    my $query = shift || '';
    my $page_num = shift || '';

    my $url = $DOMAIN.'/search?string='.$query;
    if ( $page_num ) {
        $url .= qq{&pageNum=$page_num};
    }

    my $dom = $self->dom( $url );
    my $info = $self->get_info;
    my $products_on_page = $self->get_products;

    return {
        'info'  => $info,
        'query' => $query,
        %{$products_on_page}
    };
}

# ----------------------------------------------------------------
# $filters = get_filters( $page )
# ----------------------------------------------------------------
# Get filters information for target filter page
# $filters - structure of $FILTERS_INFO type
# ----------------------------------------------------------------

sub get_filters {
    my $self = shift;
    my $filter_page = shift;

    my $url = $DOMAIN.$filter_page;
    my $dom = $self->dom( $url );

    return {
        'action'        => '',
        'csrf'          => '',
        'sort_by'       => [],
        'filters'       => [],
    };
}

# ----------------------------------------------------------------
# $item = get_item( $item_page )
# ----------------------------------------------------------------
# Item info
# $ite, - structure of $ITEM_INFO type
# ----------------------------------------------------------------

sub get_item {
    my $self = shift;
    my $item_page = shift || '';

    my $url = $DOMAIN.$item_page;
    my $dom = $self->dom( $url );
    my $info = $self->get_info;

    # Title, rating and in stock status
    my $goods_id = '';
    if ( $item_page =~ /\/goods\/(\d*)/  ) {
        $goods_id = $1;
    }
    my $title = as_clear( $self->get_item_content( 'b-details__name' ) );

    my $rating_block = $self->get_by_class( 'b-details__rating' );
    my @rating;
    my $rating_counter = 0;
    if ( $rating_block ) {
        @rating = $self->get_by_class( 'b-rating__item_state-active', $rating_block );
        $rating_counter = as_number( $self->get_item_content( 'b-rating__counter', $rating_block ) );
    }

    my @in_stock = $self->get_by_class( 'b-presence_instock' );

    # Parsing photos
    my @slides = $self->get_by_class( 'swiper-slide' );
    my @images;
    foreach ( @slides ) {
        my $img = $_->getElementsByTagName('img')->[0];
        if ( $img ) {
            my $src = $img->getAttribute('src') || '';
            push @images, $src if ( $src );
        }
    }

    # Parsing cost
    my $cost = 0;
    my $cost_old = 0;
    my $cost_item = $self->get_by_class( 'b-details__price_have-old' );
    if ( $cost_item ) {
        my $cost_text = $cost_item->as_text || '';
        $cost_text =~ s/[^0-9\s]//gsm;
        $cost_text =~ s/^\s+//;
        $cost_text =~ s/\s+$//;
        my @cst = split( ' ', $cost_text );
        $cost_old = $cst[0] || 0;
        $cost = $cst[1] || 0;
    }
    else {
        $cost = as_number( $self->get_item_content( 'b-details__price' ) );
    }

    # Cart status
    my $in_cart = 0;
    my $in_cart_btn = $self->get_by_class( 'b-details__basket' );
    if ( $in_cart_btn ) {
        my $href = $in_cart_btn->getAttribute('href') || '';
        if ( $href eq '/cart' ) {
            $in_cart = 1;
        }
    }

    # Description text
    my $description = as_clear( $self->get_item_content( 'b-details__description' ) );
    $description =~ s/^Заказать установку//;
    $description =~ s/читать далее$//;

    # Product descriptions items
    my @ditems;
    my $top_div = $self->get_by_class( 'b-product-list' );
    if ( $top_div ) {
        my $d_group = {
            'header'    => '',
            'props'     => [],
        };

        foreach my $node ( $top_div->childNodes ) {
            next if ( ref($node) =~ /Text/ );
            my $node_class = $node->getAttribute('class') || '';

            if ( $node_class eq 'b-product-list__header' ) {
                if ( @{$d_group->{'props'}} ) {
                    push @ditems, $d_group;
                    $d_group = {
                        'header'    => '',
                        'props'     => [],
                    };
                }

                $d_group->{'header'} = as_clear( $node->as_text );
            }

            if ( $node_class eq 'b-product-list__item' ) {
                my $val = as_clear( $self->get_item_content( 'b-product-list__val', $node ) );
                my $prop = as_clear( $self->get_item_content( 'b-product-list__prop', $node ) );
                push @{$d_group->{'props'}}, [ $val, $prop ];
            }
        }

        if ( @{$d_group->{'props'}} ) {
            push @ditems, $d_group;
        }
    }

    # Check back btn
    my $back = '';
    my @bk = $self->get_by_class( 'b-ico_back' );
    if ( @bk ) {
        my $top_a = $bk[0]->parentNode;
        if ( $top_a ) {
            $back = $top_a->getAttribute('href') || '';
        }
    }
    else {
        foreach ( $self->get_by_class( 'b-mobile-menu' ) ) {
            my $href = $_->getAttribute('href') || '';
            if ( $href =~ /^\/(catalog|search)/ ) {
                $back = $href;
                last;
            }
        }
    }

    return {
        %{$PRODUCT_ITEM},
        'goods_id'          => $goods_id,
        'href'              => $item_page,
        'back'              => $back,
        'title'             => $title,
        'img'               => shift @images,
        'cost'              => $cost,
        'cost_old'          => $cost_old,
        'in_cart'           => $in_cart,
        'rating'            => scalar( @rating ),
        'rating_counter'    => $rating_counter,
        'in_stock'          => scalar( @in_stock ),
        'text'              => $description,
        'description'       => \@ditems,
        'images'            => \@images,
        'info'              => $info,
    };
}

# ----------------------------------------------------------------
# add_to_cart( $goods_id )
# ----------------------------------------------------------------

sub add_to_cart {
    my $self = shift;
    my $goods_id = shift;

    my $url = $DOMAIN.'/goods/'.$goods_id.'/add';
    my $html = $self->get_html_page( $url );

    return $self->get_cart;
}

# ----------------------------------------------------------------
# get_cart
# ----------------------------------------------------------------

sub get_cart {
    my $self = shift;
    my $dom = shift;

    my $url = $DOMAIN.'/cart';
    if ( !$dom ) {
        $dom = $self->dom( $url );
    }
    my $info = $self->get_info;

    my @items;
    foreach my $item ( $self->get_by_class( 'b-basket__item' ) ) {
        my $cart_item = {
            'goods_id'  => '',
            'img'       => '',
            'title'     => as_clear( $self->get_item_content( 'b-basket__product-name', $item ) ),
            'cost'      => as_number( $self->get_item_content( 'b-basket__product-cost', $item ) ),
            'number'    => '',
        };

        my $img_div = $self->get_by_class( 'l-basket__product-img', $item );
        if ( $img_div ) {
            my $img = $img_div->getElementsByTagName('img')->[0];
            if ( $img ) {
                $cart_item->{'img'} = $img->getAttribute('src') || '';
            }
        }

        my $input = $self->get_by_class( 'b-basket__product-number-input', $item );
        if ( $input ) {
            $cart_item->{'goods_id'} = as_number( $input->getAttribute('data-gtm-eventproductid') );
            $cart_item->{'number'} = as_number( $input->getAttribute('value') );
        }

        if ( $cart_item->{'goods_id'} ) {
            push @items, $cart_item;
        }
    }

    return {
        'info'  => $info,
        'csrf'  => $self->csrf,
        'items' => \@items,
    };
}

sub update_cart {
    my $self = shift;
    my $goods_id = shift;
    my $diff = shift || 0;

    my $cart = $self->get_cart;
    
    my @items = @{$cart->{'items'}};
    if ( @items ) {
        my $post = {};
        
        foreach ( @items ) {
            my $this_id = $_->{'goods_id'};
            my $number = $_->{'number'};
            if ( $goods_id eq $this_id ) {
                $number += $diff;
                if ( !$number ) {
                    $number = 1;
                }
            }
            my $name = 'count_'.$this_id;
            $post->{ $name } = $number;
        }
        
        $post->{'_csrf'} = $cart->{'csrf'};
        my $url = $DOMAIN.'/cart';
        my $dom = $self->dom( $url, $post );
        $cart = $self->get_cart( $dom );
    }

    return $cart;            
}

sub inc_in_cart {
    my $self = shift;
    my $goods_id = shift;
    return $self->update_cart( $goods_id, 1 );
}

sub dec_in_cart {
    my $self = shift;
    my $goods_id = shift;
    return $self->update_cart( $goods_id, -1 );
}

sub del_from_cart {
    my $self = shift;
    my $goods_id = shift;
    
    my $url = $DOMAIN.'/cart?delete='.$goods_id;
    my $dom = $self->dom( $url );
    
    return $self->get_cart( $dom );
}

sub clear_cart {
    my $self = shift;
    my $goods_id = shift;

    my $url = $DOMAIN.'/cart/deleteAll';
    my $html = $self->get_html_page( $url );

    return $self->get_cart;
}

# ----------------------------------------------------------------
# checkout()
# ----------------------------------------------------------------

sub checkout {
    my $self = shift;
    my $shop_id = shift || '';
    my $csrf = shift || '';

    my $url = $DOMAIN;
    if ( $shop_id ) {
        $url .= '/checkout/stores/confirm?shopId='.$shop_id;
    }
    else {
        $url .= '/checkout';
    }

    if ( $shop_id ) {
        print "XML: ", $csrf, "\n";
        my @header = (
            'Referer'       => $DOMAIN.'/checkout',
            'Accept'        => '*/*',
            'X-CSRF-TOKEN'  => $csrf,
            'User-Agent'    => 'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'
        );
        $self->xml_http_request( $DOMAIN.'/checkout/shop?id='.$shop_id );        
        sleep 5;
    }

    print "CHECKOUT: ", $shop_id, " ",  $csrf, "\n";
    my $dom = $self->dom( $url );
    my $info = $self->get_info;

    my @stores;
    my @items;
    my $address = '';
    my $total_cost = 0;

    if ( !$shop_id ) {
        # Store list
        my $store_block = $dom->getElementById('city');
        if ( $store_block ) {
            foreach my $sto ( $self->get_by_class( 'b-store', $store_block ) ) {
                my $store = {
                    'shop_id'   => 0,
                    'title'     => '',
                    'address'   => '',
                    'avail'     => '',
                };

                my $a = $self->get_by_class( 'b-store__info', $sto );
                if ( $a ) {
                    $store->{'shop_id'} = as_number( $a->getAttribute('data-shop-id') );
                }

                $store->{'title'} = as_clear( $self->get_item_content( 'b-metro__name', $sto ) );
                $store->{'address'} = as_clear( $self->get_item_content( 'b-store__address', $sto ) );
                $store->{'avail'} = as_clear( $self->get_item_content( 'b-store__presence', $sto ) );

                if ( $store->{'shop_id'} ) {
                    push @stores, $store;
                }
            }
        }
    }
    else {
        # Checkout address
        my $dl = $self->get_by_class( 'info-list' );
        my @vl;
        foreach ( $self->get_by_class( 'value', $_ ) ) {
            push @vl, as_clear( $_->as_text );
        }
        if ( $vl[1]) {
            $address = $vl[1];
        }

        # Order items
        foreach my $item ( $self->get_by_class( 'item' ) ) {
            my $order_item = {
                'goods_id'  => as_number( $self->get_item_content( 'art', $item ) ),
                'title'     => as_clear( $self->get_item_content( 'title', $item ) ),
                'cost'      => as_number( $self->get_item_content( 'price', $item ) ),
                'number'    => as_number( $self->get_item_content( 'count', $item ) ),
            };
            push @items, $order_item;
        }

        $total_cost = as_number( $self->get_item_content( 'total_price' ) );
    }

    return {
        'info'          => $info,
        'shop_id'       => $shop_id,
        'address'       => $address,
        'total_cost'    => $total_cost,
        'stores'        => \@stores,
        'items'         => \@items,
    };
}

sub confirm {
    my $self = shift;
    my $shop_id = shift || '';
    my $csrf = shift || '';

    my $url = $DOMAIN;
    $url .= '/checkout/stores/confirm';

    print "CONFIRM $shop_id $csrf\n";
    
    my $post = {
        '_csrf'     => $csrf,
        'phone'     => '',
        'promoCode' => '',
    };

    my @header = (
        'Referer'       => $DOMAIN.'/checkout/stores/confirm?shopId='.$shop_id,
        'Origin'        => $DOMAIN,
        'Content-Type'  => 'application/x-www-form-urlencoded',
        'Accept'        => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'User-Agent'    => 'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36'
    );

    my $dom = $self->dom( $url, $post, \@header );
    #$dom = $self->dom( $DOMAIN.'/checkout/stores/success' );
    
    my $order_id = ''; 
    my $payment_btn = $self->get_by_class( 'js-gtm-pay-now' );
    if ( $payment_btn ) {
        $order_id = $payment_btn->getAttribute( 'data-gtm-event-context' ) || '';
    }

    return $order_id;    
}

# ----------------------------------------------------------------
# City settings management
# ----------------------------------------------------------------

sub csrf {
    my $self = shift;

    my $csrf = '';
    foreach ( $self->dom->getElementsByTagName('input') ) {
        my $name = $_->getAttribute('name') || '';
        if ( $name eq '_csrf' ) {
            $csrf = $_->getAttribute('value') || '';
            last;
        }
    }

    if ( !$csrf ) {
        foreach ( $self->dom->getElementsByTagName('meta') ) {
            my $name = $_->getAttribute('name') || '';
            if ( $name eq '_csrf' ) {
                $csrf = $_->getAttribute('content') || '';
                last;
            }
        }
    }

    return $csrf;
}

sub get_state_city_list {
    my $self = shift;

    my $url = $DOMAIN.'/listCities';
    my $dom = $self->dom( $url );
    my $info = $self->get_info;

    my @items;
    foreach my $item ( $self->get_by_class( 'b-city-list__item' ) ) {
        my $city = {
            'city_id'   => as_number( $item->getAttribute('data-send-data') ),
            'title'     => as_clear( $item->getAttribute('data-gtm-eventcontent') ),
        };
        push @items, $city;
    }

    return {
        'info'  => $info,
        'csrf'  => $self->csrf,
        'items' => \@items,
    };
}

sub get_city_list {
    my $self = shift;
    my $state_city_id = shift;
    my $csrf = shift;

    my $url = $DOMAIN.'/selectStateCityById';
    my $dom = $self->dom( $url, {
        'cityId'    => $state_city_id,
        '_csrf'     => $csrf
    });

    my $info = $self->get_info;

    my @items;
    foreach my $item ( $self->get_by_class( 'b-city-list__item' ) ) {
        my $city = {
            'city_id'   => as_number( $item->getAttribute('data-send-data') ),
            'title'     => as_clear( $item->getAttribute('data-gtm-eventcontent') ),
        };
        push @items, $city;
    }

    return {
        'info'  => $info,
        'state' => as_clear( $self->get_item_content( 'g-small-text' ) ),
        'csrf'  => $self->csrf,
        'items' => \@items,
    };
}

sub set_city {
    my $self = shift;
    my $city_id = shift;
    my $csrf = shift;

    my $url = $DOMAIN.'/selectCityById';
    my $dom = $self->dom( $url, {
        'cityId'    => $city_id,
        '_csrf'     => $csrf
    });

    my $info = $self->get_info;

    return {
        'info'  => $info,
    };
}

# ----------------------------------------------
# Utility
# ----------------------------------------------

sub as_clear {
    my $text = shift || '';
    $text =~ s/(\\r|\\n)//gsm;
    $text =~ s/(\r|\n)//gsm;
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+//g;
    $text =~ s/\s+$//g;
    return $text;
}

sub as_number {
    my $text = shift || '';
    $text =~ s/[^0-9]//gsm;
    $text = 0 if ( !$text );
    return $text;
}

1;