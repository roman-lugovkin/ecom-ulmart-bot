use warnings;
use strict;
use utf8;
use JSON;

# ---------------------------------------------------------------
# Telegram bot form ulmart.ru
# Created for http://www.akit.ru/olimpiada/
# Author: Lugovkin Roman, roman.lugovkin@gmail.com
# ---------------------------------------------------------------

use lib './lib';
use ECOM::Telegram::UlmartBot;

$| = 1;

# NOTE: You must describe bot token in new( 'token' => '...' )!!!

my $tlg = ECOM::Telegram::UlmartBot->new;
my $r = $tlg->run( 1 );