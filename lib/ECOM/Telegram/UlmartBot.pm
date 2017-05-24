package ECOM::Telegram::UlmartBot;

use strict;
use warnings;
use vars qw(@ISA);
use utf8;
use Encode;
use JSON;

# ---------------------------------------------------------------
# Telegram bot form ulmart.ru
# Created for http://www.akit.ru/olimpiada/
# Author: Lugovkin Roman, roman.lugovkin@gmail.com
# ---------------------------------------------------------------

use ECOM::Telegram::API::Message;

use ECOM::Telegram::Bot;
use parent 'ECOM::Telegram::Bot';

my $TOKEN = '395198585:AAF_Hm8jJqtvw5rB8dNEwPSUnufGOzOwRjA';
my $LOGO = 'https://23213p.r.fast.ulmart.ru/resources/desktop.blocks/b-head-logo/ulmart-logo.png';

sub init {
    my $self = shift;

    $self->{'token'} = $TOKEN;

    $self->SUPER::init( @_ );

    return $self;
}

# ----------------------------------------------------
# Command handlers
# ----------------------------------------------------

sub cmd_start {
    my $self = shift;
    my $up = shift;
    my $chat = shift;

    my $logo = ECOM::Telegram::API::Message->new( 'method' => 'sendPhoto' );
    $logo->{'msg'}->{'photo'} = $LOGO;

    my $text = ECOM::Telegram::API::Message->new;
    $text->{'msg'}->{'text'} = 'Здравствуйте, '.$chat->{'chat'}->{'last_name'}.' '.$chat->{'chat'}->{'first_name'}."\n";
    $text->{'msg'}->{'text'} .= qq{Используйте команду /menu для возврата в главное меню или /help для получения помощи.};

    $self->attach_status_keyboard( $chat, $text );

    return ( $logo, $text );
}

# ----------------------------------------------------
# Base menu and help
# ----------------------------------------------------

sub cmd_menu {
    my $self = shift;
    my $up = shift;
    my $chat = shift;

    my $logo = ECOM::Telegram::API::Message->new->photo( $LOGO );

    $self->attach_status_keyboard( $chat, $logo );

    return $logo;
}

sub cmd_help {
    my $self = shift;
    my $up = shift;
    my $chat = shift;

    my $help = ECOM::Telegram::API::Message->new;
    $help->text(qq{Тестовый чат-бот для работы с интернет-магазином ulmart.ru});
    $self->attach_status_keyboard( $chat, $help );

    return $help;
}

# ----------------------------------------------------
# View catalog and search
# ----------------------------------------------------

sub products_list {
    my $self = shift;
    my $catalog = shift;
    my $header = shift;

    $header->in_row( 5 );
    $header->{'msg'}->{'text'} .= qq{\n\n};

    # Products list and select btns
    my $counter = 0;
    foreach my $product ( @{$catalog->{'products'}} ) {
        $counter ++;
        my $in_stock = $product->{'in_stock'} ? '<i>В наличии</i>' : '<i>На заказ</i>';
        $header->{'msg'}->{'text'} .= qq{<b>$counter.</b> $product->{'title'}\n$in_stock\nЦена: <b>$product->{'cost'} руб.</b>\n\n};
        $header->add_inline_btn( $counter, 'item '.$product->{'href'} );
    }
    $header->{'msg'}->{'text'} .= qq{Нажмите кнопку с номером товара для просмотра подробной информации и заказа.};

    # Pagination
    my $pages = $catalog->{'pages'} || 1;
    my $active_page = $catalog->{'active_page'} || 1;
    if ( $pages > 1 ) {
        my $next_cmd = 'nop nop';
        my $prev_cmd = 'nop nop';
        if ( $active_page < $pages ) {
            my $next_page = $active_page + 1;
            $next_cmd = $catalog->{'next'}.$next_page;
        }
        if ( $active_page > 1 ) {
            my $prev_page = $active_page - 1;
            $prev_cmd = $catalog->{'prev'}.$prev_page;
        }

        my $back_cmd = 'nop nop';
        if ( $catalog->{'back'} ) {
            my $bk = $catalog->{'back'};
            if ( $bk =~ /\/catalog/ ) {
                $back_cmd = qq{catalog $bk};
            }
            elsif ( $bk =~ /\/search\?string=(.+)(&pageNum=(\d+))?$/ ) {
                my $query = $1;
                my $page = $3;
                if ( $page ) {
                    $back_cmd = qq{search $query page${page}};
                }
                else {
                    $back_cmd = qq{search $query};
                }
            }
        }

        $header->{'msg'}->{'text'} .= qq{\n\nУправляйте перемещением по списку кнопками <i>"Назад"</i> и <i>"Вперед"</i>. Нажатие <i>средней кнопки</i> вернет вас в раздел каталога.};

        $header->add_paginator( [
            { 'text' => qq{Назад}, 'callback_data' => $prev_cmd },
            { 'text' => qq{$active_page из $pages}, 'callback_data' => $back_cmd },
            { 'text' => qq{Вперед}, 'callback_data' => $next_cmd },
        ]);
    }
    
    return $header;
}

sub cmd_search {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $query = shift || '';
    
    my @ret;
    
    if ( !$query ) {
        my $info = ECOM::Telegram::API::Message->new;
        $info->text( qq{<b>Поиск</b>\nВведите поисковый запрос:} );
        $chat->state( 'search', '' );
        return $info;
    }

    my $page = 0;
    my @qr = split( ' ', $query );
    my $last_param = $qr[-1] || '';
    if ( $last_param =~ /^page(\d+)$/ ) {
        $page = $1;
        pop @qr;
        $query = join( ' ', @qr );
    }

    my $notice = ECOM::Telegram::API::Message->new;
    $notice->text( qq{Ваш запрос обрабатывается...} );
    $self->send_messages(
        'chat'      => $chat,
        'messages'  => [ $notice ],
    );
    
    my $search = $chat->search( $query, $page );
    if ( @{$search->{'products'}} ) {
        $search->{'next'} = qq{search $query page};
        $search->{'prev'} = qq{search $query page};

        my $header = ECOM::Telegram::API::Message->new;
        $header->text( qq{<b>Поиск</b>\nРезультаты поиска по запросу\n<b>$query</b>} );
        $header = $self->products_list( $search, $header );
        push @ret, $header;
    }
    else {
        my $empty = ECOM::Telegram::API::Message->new;
        $empty->text( qq{<b>Поиск</b>\nРезультаты поиска по запросу\n<b>$query<b>\n\n<i>Ничего не найдено</i>} );
        push @ret, $empty;
    }
    
    return @ret;
}

sub cmd_catalog {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $cmd_data = shift || '/catalog';

    my $text = ECOM::Telegram::API::Message->new;
    $text->text( 'Каталог' );

    my $part = $cmd_data;
    my $page = 0;
    if ( $cmd_data =~ /^(.+?)\s(\d+?)$/ ) {
        $part = $1;
        $page = $2;
    }

    # Market request
    my $catalog = $chat->get_catalog( $part, $page );

    # header
    if ( $catalog->{'title'}  ) {
        if ( @{$catalog->{'items'}} ) {
            $text->text( qq{$catalog->{'title'}} );
        }
        else {
            $text->text( qq{$catalog->{'title'} ($catalog->{'counter'})} );
        }
    }

    my $paginator;

    if ( @{$catalog->{'items'}} ) {
        # make catalog menu
        foreach my $item ( @{$catalog->{'items'}} ) {
            $text->add_inline_btn( $item->{'title'}, 'catalog '.$item->{'href'} );
        }
    }
    else {
        if ( @{$catalog->{'products'}} ) {
            $catalog->{'next'} = qq{catalog $catalog->{'url'} };
            $catalog->{'prev'} = qq{catalog $catalog->{'url'} };
            $text = $self->products_list( $catalog, $text );
        }
    }

    my @ret = ( $text );
    push @ret, $paginator if ( defined $paginator );

    return @ret;
}

# ----------------------------------------------------
# View item
# ----------------------------------------------------

sub cmd_item {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $page = shift;
    
    my @ret;

    # Market request
    my $item = $chat->get_item( $page );
    
    if ( !$item->{'title'} ) {
        my $error = ECOM::Telegram::API::Message->new;
        $error->text(qq{*Ошибка*\nПроизошла ошибка при запросе данных. Повторите, пожалуйста, свой запрос.});
        return $error;
    }

    my $in_stock = $item->{'in_stock'} ? '<i>В наличии</i>' : '<i>На заказ</i>';

    my $header = ECOM::Telegram::API::Message->new;
    my $header_text = qq{<b>$item->{'title'}</b>\n$in_stock\nАрт.: $item->{'goods_id'}\n};
    $header_text .= qq{Рейтинг: $item->{'rating'} из 5 ($item->{'rating_counter'} голосов)\n\n<b>Цена: $item->{'cost'} руб.</b>};
    $header->text( $header_text );
    push @ret, $header;
    
    if ( $item->{'img'} ) {
        my $img = ECOM::Telegram::API::Message->new->photo( $item->{'img'} );
        push @ret, $img;
    }    
    
    my $descr = ECOM::Telegram::API::Message->new;
    my $descr_text = qq{\n<i>$item->{'text'}</i>};
    foreach my $d_group ( @{$item->{'description'}} ) {
        $descr_text .= qq{\n\n<b>$d_group->{'header'}</b>};
        foreach my $prop ( @{$d_group->{'props'}} ) {
            $descr_text .= qq{\n$prop->[0]: $prop->[1]};
        }
    }
    $descr_text .= qq{\n\n$in_stock\n\n};

    if ( $item->{'in_cart'} ) {
        $descr_text .= qq{<b>Уже в корзине</b>\n\n};
    }
    else {
        $descr->add_inline_btn( qq{Купить за $item->{'cost'} руб.}, qq{add $item->{'goods_id'}} );
    }
    
    $descr->text( $descr_text );
    
    if ( $item->{'back'} ) {
        my $back_cmd = '';
        if ( $item->{'back'} ) {
            my $bk = $item->{'back'};
            if ( $bk =~ /\/catalog/ ) {
                $back_cmd = qq{catalog $bk};
            }
            elsif ( $bk =~ /\/search\?string=(.+)(&pageNum=(\d+))?$/ ) {
                my $query = $1;
                my $page = $3;
                if ( $page ) {
                    $back_cmd = qq{search $query page${page}};
                }
                else {
                    $back_cmd = qq{search $query};
                }
            }
        }
        $descr->add_inline_btn( 'Вернуться в каталог', $back_cmd );
    }
    
    push @ret, $descr;
    
    return @ret;
}

# ----------------------------------------------------
# City management
# ----------------------------------------------------

sub cmd_city {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $city_param = shift || '';
    
    my @pr = split( ' ', $city_param );
    my $city_id = shift @pr;
    my $csrf = shift @pr;
    
    my $city = $chat->get_city( $city_id, $csrf );
    my $header = ECOM::Telegram::API::Message->new;
    if ( $city_id ) {
        my $state_city = $city->{'state'} || '';
        $header->text( qq{Областной город: <b>$state_city</b>\nВыберите город} );
    }
    else {
        $header->text( qq{Выберите областной город} );
    }

    if ( @{$city->{'items'}} ) {
        # make city select list
        foreach my $item ( @{$city->{'items'}} ) {
            if ( $city_id ) {
                $header->add_inline_btn( $item->{'title'}, 'setcity '.$item->{'city_id'}.' '.$city->{'csrf'} );
            }
            else {
                $header->add_inline_btn( $item->{'title'}, 'city '.$item->{'city_id'}.' '.$city->{'csrf'} );
            }
        }
    }
    
    return $header;
}

sub cmd_setcity {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $city_param = shift || '';
    
    my @pr = split( ' ', $city_param );
    my $city_id = shift @pr;
    my $csrf = shift @pr;

    my $city = $chat->set_city( $city_id, $csrf );

    my $header = ECOM::Telegram::API::Message->new;
    $header->text( qq{Установлен текущий город\n<b>$city->{'info'}->{'city'}</b>\n} );
    $self->attach_status_keyboard( $chat, $header, $city->{'info'} );

    return $header;    
}

# ----------------------------------------------------
# Shopping cart management
# ----------------------------------------------------

sub cmd_cart {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $cart = shift;

    my @ret;
    
    if ( !$cart ) {
        $cart = $chat->get_cart;
    }
    
    my $info = $cart->{'info'};
    my @items = @{$cart->{'items'}};
    
    if ( !@items ) {
        my $empty = ECOM::Telegram::API::Message->new;
        $empty->text( qq{<b>Ваша корзина</b>\n\nВаша корзина пуста.\n\n} );
        $self->attach_status_keyboard( $chat, $empty, $info );
        return $empty;        
    }
    
    my $header = ECOM::Telegram::API::Message->new;
    my $header_text = qq{<b>Ваша корзина</b>\n\nТоваров: <b>$info->{'cart_counter'}</b>\nНа сумму: <b>$info->{'cart_cost'} руб.</b>};
    $header->text( $header_text );
    $self->attach_status_keyboard( $chat, $header, $info );
    push @ret, $header;
    
    foreach my $item ( @items ) {
        my $item_msg = ECOM::Telegram::API::Message->new;
        $item_msg->text(qq{\n<b>$item->{'title'}</b>\n$item->{'cost'} руб. x $item->{'number'} шт.\n});
        
        my $dec_code = 'nop nop';
        if ( $item->{'number'} > 1 ) {
            $dec_code = qq{dec $item->{'goods_id'}};
        }
        
        $item_msg->add_inline_btn( 'Меньше', $dec_code );
        $item_msg->add_inline_btn( 'Больше', qq{inc $item->{'goods_id'}} );
        $item_msg->add_inline_btn( 'Убрать', qq{del $item->{'goods_id'}} );

        $item_msg->in_row( 3 ); 
        
        push @ret, $item_msg;
    }

    if ( @items ) {
        my $footer = ECOM::Telegram::API::Message->new;
        $footer->text( qq{\n<b>Итого: $info->{'cart_cost'} руб.</b>\n\n} );
        $footer->add_inline_btn( qq{Оформить самовывоз}, qq{checkout 0 $info->{'csrf'}} );
        $footer->add_inline_btn( qq{Очистить корзину}, 'clear' );
        push @ret, $footer;
    }
    
    return @ret;
}

sub cmd_add {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $goods_id = shift;

    my $notice = ECOM::Telegram::API::Message->new;
    $notice->text( qq{Ваш запрос обрабатывается...} );
    $self->send_messages(
        'chat'      => $chat,
        'messages'  => [ $notice ],
    );

    my @ret;
    my $cart = $chat->add_to_cart( $goods_id );
    
    $notice = ECOM::Telegram::API::Message->new;
    $notice->text('Товар добавлен в корзину');
    $self->attach_status_keyboard( $chat, $notice, $cart->{'info'} );
    push @ret, $notice; 
    
    push @ret, $self->cmd_cart( $up, $chat, $cart );
    
    return @ret;
}

sub cmd_inc {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $goods_id = shift;

    my @ret;
    my $cart = $chat->inc_in_cart( $goods_id );
    push @ret, $self->cmd_cart( $up, $chat, $cart );
    
    return @ret;
}

sub cmd_dec {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $goods_id = shift;

    my @ret;
    my $cart = $chat->dec_in_cart( $goods_id );
    push @ret, $self->cmd_cart( $up, $chat, $cart );
    
    return @ret;
}

sub cmd_del {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $goods_id = shift;

    my @ret;
    my $cart = $chat->del_from_cart( $goods_id );
    push @ret, $self->cmd_cart( $up, $chat, $cart );
    
    return @ret;
}

sub cmd_clear {
    my $self = shift;
    my $up = shift;
    my $chat = shift;

    my @ret;
    my $cart = $chat->clear_cart;
    push @ret, $self->cmd_cart( $up, $chat, $cart );
    
    return @ret;
}

# ----------------------------------------------------
# Checkout processing
# ----------------------------------------------------

sub cmd_confirm {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $data = shift || '';
    
    my @pr = split( ' ', $data );
    my $shop_id = shift @pr;
    my $csrf = shift @pr;

    my @ret;
    
    my $notice = ECOM::Telegram::API::Message->new;
    $notice->text( qq{Ваша заявка обрабатывается...} );
    $self->send_messages(
        'chat'      => $chat,
        'messages'  => [ $notice ],
    );
    
    my $order_id = $chat->confirm( $shop_id, $csrf );
    if ( !$order_id ) {
        my $error = ECOM::Telegram::API::Message->new;
        $error->text( qq{\n<b>Ошибка</b>\nОшибка обработки заказа.\nПожалйста, попробуйте еще раз.} );
        push @ret, $error;
    }
    else {
        my $done = ECOM::Telegram::API::Message->new;
        $done->text( qq{\n<b>Спасибо за заказ!</b>\n\nВаш номер заказа: <b>$order_id</b>\n});
        
        my $info = $chat->get_info;
        $self->attach_status_keyboard( $chat, $done, $info );
        
        push @ret, $done;
    }
    
    return @ret;    
}

sub cmd_checkout {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $data = shift || '';
    
    my @pr = split( ' ', $data );
    my $shop_id = shift @pr;
    my $csrf = shift @pr;
    
    my @ret;
    
    if ( $shop_id ) {
        my $notice = ECOM::Telegram::API::Message->new;
        $notice->text( qq{Ваша заявка обрабатывается...} );
        $self->send_messages(
            'chat'      => $chat,
            'messages'  => [ $notice ],
        );
    }
    
    my $checkout = $chat->checkout( $shop_id, $csrf );
    if ( !$shop_id ) {
        my $header = ECOM::Telegram::API::Message->new;
        my $header_text = qq{\n<b>Адреса магазинов и пунктов самовывоза</b>\n\n};
        
        my $counter = 0;
        foreach my $store ( @{$checkout->{'stores'}} ) {
            $counter ++;
            $header_text .= qq{<b>$counter. $store->{'title'}</b>\n$store->{'address'}\n<i>$store->{'avail'}</i>\n\n};
            $header->add_inline_btn( $counter, 'checkout '.$store->{'shop_id'} );
        }
        
        $header_text .= qq{Нажмите кнопку с номером пункта для оформления заказа.\n\n};
        $header->text( $header_text );
        $header->in_row( 5 );
        push @ret, $header;
    }
    else {
        my $header = ECOM::Telegram::API::Message->new;
        my $header_text = qq{\n<b>Ваш заказ</b>\n\n};

        my $counter = 0;
        foreach my $item ( @{$checkout->{'items'}} ) {
            $counter ++;
            $header_text .= qq{<b>$counter. $item->{'title'}</b>\n$item->{'cost'} руб. x $item->{'number'} шт.\n\n};
        }
        $header_text .= qq{<b>Итого к оплате: $checkout->{'total_cost'} руб.</b>\n\n};
        $header_text .= qq{<b>Заберу отсюда:</b> $checkout->{'address'}\n};
        $header->text( $header_text );

        $header->add_inline_btn( 'Подтвердить', 'confirm '.$shop_id.' '.$checkout->{'info'}->{'csrf'} );
        push @ret, $header;
    }
    
    return @ret;
}

# ----------------------------------------------------
# Attach keybords
# ----------------------------------------------------

sub attach_status_keyboard {
    my $self = shift;
    my $chat = shift;
    my $msg = shift;
    my $last_info = shift;

    my $info = $last_info;
    
    if ( !defined $info ) {
        my $data_ref = $chat->data;
        if ( $data_ref and ( !%{$data_ref->{'last_info'}} ) ) {
            $data_ref = $chat->get_info;
        }
    
        $info = $data_ref->{'last_info'} || {};
    } 

    $info->{'city'} = $info->{'city'} || 'Город: Не выбран';

    $msg->add_btn( qq{Каталог /catalog} );
    $msg->add_btn( qq{Поиск /search} );
    $msg->add_btn( qq{$info->{'city'} /city} );
    $msg->add_btn( qq{Товаров: $info->{'cart_counter'} на $info->{'cart_cost'} руб. /cart} );
    #$msg->in_row( 2 );

    return $msg;
}

1;