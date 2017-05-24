package ECOM::Telegram::Bot;

use strict;
use warnings;
use vars qw(@ISA);
use utf8;
use Encode;
use JSON;
use LWP;
use HTTP::Headers;
use HTTP::Request;

# ---------------------------------------------------------------
# Telegram bot form ulmart.ru
# Created for http://www.akit.ru/olimpiada/
# Author: Lugovkin Roman, roman.lugovkin@gmail.com
# ---------------------------------------------------------------

use ECOM::Telegram::API::Chat;
use ECOM::Telegram::API::Message;

my $DONE = {};
my $CHATS = {};

sub new {
    my $instance = shift;
    my $class = ref($instance) || $instance;

    my $self = {
        'token'         => '',
        @_,
        'ua'            => undef,
    };

    bless($self, $class);
    return $self->init;
}

sub init {
    my $self = shift;

    my $ua = LWP::UserAgent->new;
    $self->{'ua'} = $ua;

    return $self;
}

# ----------------------------------------------
# Process update pool
# ----------------------------------------------

sub process_current_pool {
    my $self = shift;
    my $last_id = shift;

    my $updates = $self->get_updates( $last_id );

    open FP, ">>last-pool.json";
    print FP to_json( $updates, { 'pretty' => 1, 'utf8' => 1 } );
    close FP;

    my $last_update_id = 0;

    if ( !$updates->{'error'} and $updates->{'data'}->{'ok'} ) {
        my $list = $updates->{'data'}->{'result'} || [];
        foreach my $up ( @{$list} ) {
            my $up_id = $up->{'update_id'};
            unless ( exists $DONE->{ $up_id } ) {
                my $msg = $up->{'message'};
                my @answer;
                my $command = '';
                my $cmd_data = '';

                if ( $up->{'callback_query'} ) {
                    my $cq = $up->{'callback_query'};
                    $msg = $cq->{'message'};
                    my $data = $cq->{'data'};
                    my @dt = split( ' ', $data );
                    $command = shift @dt;
                    $cmd_data = join( ' ', @dt );
                }

                # Active chat session object
                my $chat_id = $msg->{'chat'}->{'id'};
                my $chat;
                if ( exists $CHATS->{ $chat_id } ) {
                    $chat = $CHATS->{ $chat_id };
                }
                else {
                    $chat = ECOM::Telegram::API::Chat->new( 'chat' => $msg->{'chat'} );
                    $CHATS->{ $chat_id } = $chat;
                }

                # Process commands
                if ( $command ) {
                    my $method_name = 'cmd_'.$command;
                    my $sub = $self->can( $method_name );
                    if ( ref( $sub ) eq 'CODE' ) {
                        print $msg->{'message_id'}, " ", $command, "\n";
                        push @answer, $self->$sub( $up, $chat, $cmd_data );
                    }
                }
                else {
                    if ( $msg->{'entities'} ) {
                        foreach my $e ( @{$msg->{'entities'}} ) {
                            if ( $e->{'type'} eq 'bot_command' ) {
                                $command = substr( $msg->{'text'}, $e->{'offset'} + 1, $e->{'length'} - 1 );
                                my $method_name = 'cmd_'.$command;
                                my $sub = $self->can( $method_name );
                                if ( ref( $sub ) eq 'CODE' ) {
                                    print $msg->{'message_id'}, " ", $command, "\n";
                                    push @answer, $self->$sub( $up, $chat );
                                }
                            }
                        }
                    }
                }
                
                # Check state machine
                if ( !@answer ) {
                    my ( $state, $state_data ) = $chat->state;
                    if ( $state ) {
                        $command = $state;
                        $cmd_data = $state_data || $msg->{'text'};
                        
                        my $method_name = 'cmd_'.$command;
                        my $sub = $self->can( $method_name );
                        if ( ref( $sub ) eq 'CODE' ) {
                            print $msg->{'message_id'}, " ", $command, "\n";
                            push @answer, $self->$sub( $up, $chat, $cmd_data );
                        }
                        
                        $chat->reset_state;
                    }
                }

                if ( !@answer ) {
                    push @answer, $self->cmd_unknown( $up, $chat );
                }

                $DONE->{ $up_id } = $self->send_messages( 'chat' => $chat, 'messages' => \@answer, 'reply_to' => $msg );
                $last_update_id = $up_id;
            }
        }
    }

    return $last_update_id;
}

# ----------------------------------------------
# Main point
# ----------------------------------------------

sub run {
    my $self = shift;
    my $mode = shift || 0; 

    my $uid = 0;
    
    if ( $mode ) {
        while ( 1 ) {
            sleep $mode;
            $uid = $self->process_current_pool( $uid );
        }
    }
    else {
        while ( $uid = $self->process_current_pool( $uid ) ) {
            sleep 1;
        }
    }

    return $self;
}

# ----------------------------------------------
# Send answers to chat
# ----------------------------------------------

sub send_messages {
    my $self = shift;
    my $params = {
        'chat'      => undef,
        'messages'  => [],
        'reply_to'  => {},
        @_
    };

    my $chat = $params->{'chat'};
    foreach my $message ( @{$params->{'messages'}} ) {
        next unless ( $message );

        my $msg = $self->post_process_message( $params->{'chat'}, $message )->msg;
        $msg->{'chat_id'} = $chat->chat_id;

        my $r = $self->request( $message->method, $msg );

        open FP, ">>send.json";
        print FP to_json( { 'send' => $msg, 'answer' => $r }, { 'pretty' => 1, 'utf8' => 1 } );
        close FP;
    }

    return 1;
}

# ----------------------------------------------
# Unknown command process
# ----------------------------------------------

sub cmd_unknown {
    my $self = shift;
    my $up = shift;
    my $chat = shift;
    my $cmd_data = shift;
    return;
}

sub post_process_message {
    my $self = shift;
    my $chat = shift;
    my $message = shift;

    return $message;
}

# ----------------------------------------------
# Get bot updates
# ----------------------------------------------

sub get_updates {
    my $self = shift;
    my $last_id = shift || 0;

    if ( $last_id ) {
        $last_id ++;
    }

    my $updates = $self->request( 'getUpdates', { 'offset' => $last_id } );
    return $updates;
}

# ----------------------------------------------
# Utility
# ----------------------------------------------

sub token {
    my $self = shift;
    return $self->{'token'};
}

sub ua {
    my $self = shift;
    return $self->{'ua'};
}

sub request {
    my $self = shift;
    my $method = shift;
    my $post = shift;

    my $token = $self->token;
    my $url = qq{https://api.telegram.org/bot$token/$method};

    my $r;
    if ( defined $post ) {
        my $h = HTTP::Headers->new('Content_Type' => 'application/json' );
        my $rq = HTTP::Request->new( 'POST', $url, $h, encode( 'utf8', to_json( $post ) ) );
        $r = $self->ua->request( $rq );
    }
    else {
        $r = $self->ua->get( $url );
    }

    my $response = {
        'error' => '',
    };

    if ( $r->is_success ) {
        my $content = decode( 'utf8', $r->content );
        my $data;
        eval {
            $data = from_json( $content );
        };

        if ( !$@ ) {
            $response->{'data'} = $data;
        }
        else {
            $response->{'error'} = $@;
        }
    }
    else {
        $response->{'error'} = $r->status_line;
    }

    return $response;
}

1;