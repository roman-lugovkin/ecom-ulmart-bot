package ECOM::Telegram::API::Message;

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

sub new {
    my $instance = shift;
    my $class = ref($instance) || $instance;

    my $self = {
        'method'            => 'sendMessage',
        'msg'               => {
            'parse_mode'                => 'HTML',
            'text'                      => 'Hm...',
            'disable_web_page_preview'  => 1,
        },
        'inline_as_calc'    => 0,
        @_,
        'keyboard'  => [],
        'inline'    => [],
        'paginator' => [],
    };

    bless($self, $class);
    return $self->init;
}

sub init {
    my $self = shift;
    return $self;
}

sub method {
    my $self = shift;
    if ( @_ ) {
        $self->{'method'} = shift @_;
    }
    return $self->{'method'};
}

sub text {
    my $self = shift;
    my $text = shift;
    $self->{'msg'}->{'text'} = $text;
    return $self;
}

sub in_row {
    my $self = shift;
    if ( @_ ) {
        $self->{'inline_as_calc'} = shift @_;
    }
    return $self->{'inline_as_calc'};
}

sub photo {
    my $self = shift;
    my $url = shift;
    
    if ( $url ) {
        $self->{'msg'}->{'photo'} = $url;
        delete $self->{'msg'}->{'text'};
        $self->method( 'sendPhoto' );
    }
    
    return $self;
}

sub make_by_row {
    my $self = shift;
    my @btns = @_;
    
    my @inb;
    my @row;
    my $btn;
    my $cnt = 0;
    while ( $btn = shift @btns ) {
        push @row, $btn;
        $cnt ++;
        if ( $cnt == $self->in_row ) {
            push @inb, [ @row ];
            @row = ();
            $cnt = 0;
        }
    }
    push @inb, [ @row ] if ( @row );
    
    return @inb;
}

sub msg {
    my $self = shift;

    my $msg = $self->{'msg'};
    my $kb = $self->{'keyboard'} || [];
    my $in = $self->{'inline'} || [];
    my $pg = $self->{'paginator'} || [];

    if ( @{$in} ) {
        my @btns;

        foreach ( @{$in} ) {
            if ( $self->in_row ) {
                push @btns, {
                    'text'          => $_->[0],
                    'callback_data' => $_->[1],
                };
            }
            else {
                push @btns, [{
                    'text'          => $_->[0],
                    'callback_data' => $_->[1],
                }];
            }
        }

        if ( $self->in_row ) {
             @btns = $self->make_by_row( @btns );
        }

        if ( @{$pg} ) {
            push @btns, $pg;
        }

        $msg->{'reply_markup'} = {
            'inline_keyboard'  => \@btns,
        };
    }
    elsif ( @{$kb} ) {
        my @btns;

        foreach ( @{$kb} ) {
            if ( $self->in_row ) {
                push @btns, {
                    'text'  => $_
                };
                
            }
            else {
                push @btns, [{
                    'text'  => $_
                }];
            }
        }

        if ( $self->in_row ) {
             @btns = $self->make_by_row( @btns );
        }

        $msg->{'reply_markup'} = {
            'keyboard'  => \@btns,
        };
    }

    return $msg;
}

sub add_btn {
    my $self = shift;
    my $text = shift || '';

    push @{$self->{'keyboard'}}, $text;

    return $self;
}

sub add_inline_btn {
    my $self = shift;
    my $text = shift;
    my $callback = shift || '';

    push @{$self->{'inline'}}, [ $text, $callback ];

    return $self;
}

sub add_paginator {
    my $self = shift;
    my $paginator = shift || [];

    $self->{'paginator'} = $paginator;

    return $self;
}

1;