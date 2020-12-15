# Settings.pm
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

package Plugins::PlaylistMan::Settings;
use base qw(Slim::Web::Settings);
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.PlaylistMan');

my $log = Slim::Utils::Log->addLogCategory( 
 { 
     'category'     => 'plugin.PlaylistMan', 
     'defaultLevel' => 'WARN', 
     'description'  => 'PLUGIN_PLAYLISTMAN_NAME' 
 }
);

my @FavouritePlaylists = ('Bad Music', 'Bad Tags', 'Morning Alarm');
$prefs->init({ 'FavouritePlaylists' => \@FavouritePlaylists });

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_PLAYLISTMAN_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/PlaylistMan/settings/basic.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	$log->debug("start - FavouritePlaylists=" . (ref $params->{'FavouritePlaylists'} eq 'ARRAY' ? join(",",@{$params->{'FavouritePlaylists'}}) : $params->{'FavouritePlaylists'}) );

	if ($params->{'saveSettings'}) {
		$log->debug("saveSettings");

		# Remove empty items
		my @favPlaylists = grep { $_ ne '' } (ref $params->{'FavouritePlaylists'} eq 'ARRAY' ? @{$params->{'FavouritePlaylists'}} : $params->{'FavouritePlaylists'});
		$log->debug("favPlaylists=" . join(",",@favPlaylists));
		$prefs->set('FavouritePlaylists', \@favPlaylists);
		$params->{'FavouritePlaylists'} = \@favPlaylists;
	}

	my @favPlaylists = ( @{$prefs->get('FavouritePlaylists')}, '' );
	$params->{'FavouritePlaylistsList'} = \@favPlaylists;

	$log->debug("end - FavouritePlaylistsList=" . (ref $params->{'FavouritePlaylistsList'} eq 'ARRAY' ? join(",",@{$params->{'FavouritePlaylistsList'}}) : $params->{'FavouritePlaylistsList'}) );

	return $class->SUPER::handler($client, $params);
}

sub prefs {
	return ($prefs, qw(FavouritePlaylists));
}

1;
