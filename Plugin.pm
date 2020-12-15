# Playlist Manager.pm by Philip Meyer (phil@hergest.demon.co.uk)
# Version 6.1
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Supported CLI commands:
# playlistman add track id:<id> playlist_name:<name>
# playlistman add album id:<id> playlist_name:<name>
#
# Other CLI commands will be added in the future...

use strict;

use Encode;

package Plugins::PlaylistMan::Plugin;
use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw (string);
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Client;
use Slim::Player::Playlist;
use Scalar::Util qw(blessed);
use File::Spec::Functions qw(:ALL);

use Plugins::PlaylistMan::Settings;

use vars qw($VERSION);

use constant PLAYLISTMAN_BROWSE_ADD_MENU => 'PlaylistMan.BrowseAddMenu';
use constant PLAYLISTMAN_BROWSE_TRACK_ADD_MENU => 'PlaylistMan.BrowseTrackAddMenu';

use constant PLAYLISTMAN_NOW_PLAYING_MENU => 'PlaylistMan.NowPlayingAddMenu';

use constant PLAYLISTMAN_MENU_ADD => 'PlaylistMan.SelectPlaylistMenu';
use constant PLAYLISTMAN_SELECT_OTHER_PLAYLIST => 'PlaylistMan.SelectOtherPlaylist';

my $prefs = preferences('plugin.PlaylistMan');

my $log = Slim::Utils::Log->addLogCategory( 
 { 
     'category'     => 'plugin.PlaylistMan', 
     'defaultLevel' => 'WARN', 
     'description'  => 'PLUGIN_PLAYLISTMAN_NAME' 
 }
);


our @LegalChars = (
	undef, # placeholder for rightarrrow
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
	'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
	'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	' ',
	'.', '-', '_',
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
);

our @legalMixed = (
	[' ','0'], 				                  # 0
	['.','-','_','1'], 			            # 1
	['a','b','c','A','B','C','2'],		   # 2
	['d','e','f','D','E','F','3'], 		   # 3
	['g','h','i','G','H','I','4'], 		   # 4
	['j','k','l','J','K','L','5'], 		   # 5
	['m','n','o','M','N','O','6'], 		   # 6
	['p','q','r','s','P','Q','R','S','7'], # 7
	['t','u','v','T','U','V','8'], 		   # 8
	['w','x','y','z','W','X','Y','Z','9'] 	# 9
);

our %context = ();

# These global variables are a bit of a hack.  Need a better fix for this.
my $playlistindex;
my $addItem;


sub getDisplayName()
{
	return 'PLUGIN_PLAYLISTMAN_NAME';
}

sub enabled
{
	return 1;
}

sub setMode
{
   my $class = shift;
	my $client = shift;
	my $method = shift || '';

	$log->debug("PlaylistMan set mode method=$method");
}

sub lines
{
	my $client = shift;
	my ($line1, $line2);

	return ($line1, $line2);
}

our %functions =
(
	'addmenu' => sub
	{
		my $client = shift;
		$playlistindex = Slim::Buttons::Playlist::browseplaylistindex($client);
		my $track = Slim::Player::Playlist::song($client, $playlistindex);

		$addItem = $track;
		my $trackName = $track->title;

		$log->info("PlaylistMan: display addmenu for $trackName");

		my %params =
		(
			# The header (first line) to display whilst in this mode.
			header => '{PLUGIN_PLAYLISTMAN_NAME} {count}',

			# A reference to the list of items to display.
			listRef => [
            $client->string('PLUGIN_PLAYLISTMAN_ADD_TRACK_TO'),
            $client->string('PLUGIN_PLAYLISTMAN_ZAP_TRACK'),
            $client->string('PLUGIN_PLAYLISTMAN_SAVE_NEW_PLAYLIST')
            ],

			# A unique name for this mode that won't actually get displayed anywhere.
			modeName => PLAYLISTMAN_NOW_PLAYING_MENU,

			parentMode => Slim::Buttons::Common::mode($client),

			selectedItem => $track,

			onPlay => sub {
				my ($client, $action) = @_;
				my $track = $client->modeParam('selectedItem');
				NowPlayingAddAction($client, $action, $track);
			},

			onAdd => sub {
				my ($client, $action) = @_;
				my $track = $client->modeParam('selectedItem');
				NowPlayingAddAction($client, $action, $track);
			},

			# An anonymous function that is called every time the user presses the RIGHT button.
			onRight => sub {
				my ($client, $action) = @_;
				my $track = $client->modeParam('selectedItem');
				NowPlayingAddAction($client, $action, $track);
			},

			# These are all menu items and so have a right-arrow overlay
			overlayRef => sub {
            my $client = shift; 
            return [ undef, $client->symbols('rightarrow') ];
         }
		);

		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
	}
);

sub trackInfoHandler {
	my $return = objectInfoHandler( 'track', @_);
	return $return;
}

sub albumInfoHandler {
	my $return = objectInfoHandler( 'album', @_);
	return $return;
}

sub objectInfoHandler {
	my ( $objectType, $client, $url, $obj, $remoteMeta, $tags ) = @_;

	return unless $client;

	$log->debug("objectInfoHandler for $objectType");

	return {
		type => 'redirect',
		name => $client->string('PLUGIN_PLAYLISTMAN_ADD_TO'),
		favorites => 0,

		player => {
			mode => PLAYLISTMAN_BROWSE_ADD_MENU,
			modeParams => {
				addItemType => $objectType,
				addItemId => $obj->id,
			},
		},

		jive => {
			actions => {
				go => {
					cmd => [ 'playlistman', 'add', $objectType ],
					params => {
						menu => 1,
						id => $obj->id,
					}					
				}
			}
		},

# 		web  => {
# 			url => 'plugins/PlaylistMan/index.html?track_id=' . $obj->id,
# 		},
	};
}

sub cliAddToHandler {
	$log->debug("Entering cliAddToHandler");
	my $request = shift;

	if ($request->isNotCommand([['playlistman'],['add'],['track', 'album']])) {
		$log->warn("Incorrect command: " . $request->getRequestString());
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();

	if(!defined $client) {
		$log->warn("Client required");
		$request->setStatusNeedsClient();
		return;
	}

	my $menu = $request->getParam('menu');

	my $params = $request->getParamsCopy();
	for my $k (keys %$params) {
		$log->debug("Got: $k=".$params->{$k});
	}

	my $objType = $request->getRequest(2);
	$log->debug("objType = $objType");

	my $id = $request->getParam('id');

	my $playlist_name = $request->getParam('playlist_name');

	my $obj;

	if ($objType eq 'track') {
		if (defined $id) {
			$obj = Slim::Schema->find( Track => $id );
		}
		else {
			my $track_url = $request->getParam('track_url');
			$obj = Slim::Schema->objectForUrl( {	url => $track_url } );
		}
	}
	elsif ($objType eq 'album') {
		$obj = Slim::Schema->find( Album => $id );
	}

	my $loopname = $menu ? 'item_loop' : 'titles_loop';
	my $chunkCount = 0;

	if (defined $playlist_name) {
		$log->info("Add $objType to playlist $playlist_name");
		#Add menu to select where to add the item to...
		#Or add a context menu
		AddToPlaylist($client, $playlist_name, $obj);

		$request->addResult( 'count', 1 );

		my $info = $obj->title;
		$log->info("Title $info");
  
		$client->showBriefly({
			'jive' => {
				'type'    => 'popupplay',
				'text'    => [ $client->string('JIVE_POPUP_ADDING'), $info, $client->string('PLUGIN_PLAYLISTMAN_POPUP_TO_PLAYLIST', $playlist_name) ],
			}
		});

		$request->setStatusDone();
	}
	else {
		if ($menu) {
			my $actionParams;
			if ($objType eq 'track') {
				$actionParams = { cmd => 'add', track_id => $id, };
			}
			elsif ($objType eq 'album') {
				$actionParams = { cmd => 'add', album_id => $id, };
			}

			my $otherPlaylist = $request->getParam('other_playlist');
			if (!$otherPlaylist) {
				$request->addResult('window', {
					'text' => $client->string('PLUGIN_PLAYLISTMAN_ADD_TO'),
				});

				$request->addResult('offset', 0);

				#--- Current Playlist ---
				$request->addResultLoop($loopname, $chunkCount, 'text', $client->string('PLUGIN_PLAYLISTMAN_CURRENT_PLAYLIST'));

				my $actions = {
					add => {
						player => 0,
						cmd => [ 'playlistcontrol' ],
						params => $actionParams,
						nextWindow => 'parent',
					},
				};

				# play and go have same behavior as add
				$actions->{play} = $actions->{add};
				$actions->{go} = $actions->{add};
				$request->addResultLoop($loopname, $chunkCount, 'actions', $actions);

				$chunkCount++;


				#--- Favourite Playlists ---
				for my $fav (@{$prefs->get('FavouritePlaylists')}) {
					$request->addResultLoop($loopname, $chunkCount, 'text', $fav);

					$actions = {
						add => {
		  					cmd => [ 'playlistman', 'add', $objType ],
		  					params => {
		  						id => $id,
		  						playlist_name => $fav
							},
							nextWindow => 'parent',
						},
					};
					# play and go have same behavior as add
					$actions->{play} = $actions->{add};
					$actions->{go} = $actions->{add};
					$request->addResultLoop($loopname, $chunkCount, 'actions', $actions);

					$chunkCount++;
				}


				#--- Other Playlists ---
				$request->addResultLoop($loopname, $chunkCount, 'text', $client->string('PLUGIN_PLAYLISTMAN_OTHER_PLAYLIST'));

				$actions = {
					add => {
						cmd => [ 'playlistman', 'add', $objType ],
						params => {
							menu => 1,
							other_playlist => 1,
							id => $id,
						},
					},
				};

				# play and go have same behavior as add
				$actions->{play} = $actions->{add};
				$actions->{go} = $actions->{add};
				$request->addResultLoop($loopname, $chunkCount, 'actions', $actions);

				$chunkCount++;


				#--- New Playlist ---
				$request->addResultLoop($loopname, $chunkCount, 'text', $client->string('PLUGIN_PLAYLISTMAN_NEW_PLAYLIST'));

				if ($objType eq 'track') {
					$actionParams = { cmd => 'add', track_id => $id };
				}
				elsif ($objType eq 'album') {
					$actionParams = { cmd => 'add', album_id => $id };
				}

				# ask user for name before firing the action
				# __TAGGEDINPUT__ will be replaced by the entered text in the form "search:"
				my $input = { len => 3 };
				$request->addResultLoop($loopname, $chunkCount, 'input', $input);

				$actions = {
					add => {
						cmd => [ 'playlistman', 'add', $objType ],
						params => {
	  						id => $id,
	  						playlist_name => '__TAGGEDINPUT__',
						},
						nextWindow => 'grandparent',
					},
				};

				# play and go have same behavior as add
				$actions->{play} = $actions->{add};
				$actions->{go} = $actions->{add};

				$request->addResultLoop($loopname, $chunkCount, 'actions', $actions);

				$chunkCount++;

				$request->addResult('count', $chunkCount);
			}
			else {
				# List other playlists

				$request->addResult('window', {
					'text' => $client->string('PLUGIN_PLAYLISTMAN_ADD_TO'),
				});

				$request->addResult('offset', 0);

				my $actions;

				my @otherPlaylistItems=ListOtherPlaylists();
				foreach my $playlistItem (@otherPlaylistItems) {
					$request->addResultLoop($loopname, $chunkCount, 'text', $playlistItem);

					$actions = {
						add => {
		  					cmd => [ 'playlistman', 'add', $objType ],
		  					params => {
		  						id => $id,
		  						playlist_name => $playlistItem
							},
							nextWindow => 'grandparent',
						},
					};

					# play and go have same behavior as add
					$actions->{play} = $actions->{add};
					$actions->{go} = $actions->{add};
					$request->addResultLoop($loopname, $chunkCount, 'actions', $actions);

					$chunkCount++;
				}

				$request->addResult('count', $chunkCount);
			}
		}
	}

	$request->setStatusDone();
}

sub ItemInfoAddMenu
{
	my $client = shift;
	my $method = shift;

	$log->debug("ItemInfoAddMenu: method=$method");

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $objType = $client->modeParam('addItemType');
	my $id = $client->modeParam('addItemId');

	my $obj;

	if ($objType eq 'track') {
		$obj = Slim::Schema->find( Track => $id );
	}
	elsif ($objType eq 'album') {
		$obj = Slim::Schema->find( Album => $id );
	}

	Plugins::PlaylistMan::Plugin::BrowseAddItemMenu($client, $obj);
}

sub BrowseAddMenu
{
	my $client = shift;
	my $button = shift;
	my $addorinsert = shift || 0;

	$log->debug("BrowseAddMenu: button=$button, addorinsert=$addorinsert");

	my $items       = $client->modeParam('listRef');
	my $listIndex   = $client->modeParam('listIndex');
	my $currentItem = $items->[$listIndex] || return;

	$log->debug("BrowseAddMenu: currentItem=$currentItem");

	my $hierarchy    = $client->modeParam('hierarchy');
	my $level        = $client->modeParam('level');
	my $descend      = $client->modeParam('descend');
	my $findCriteria = $client->modeParam('findCriteria');
	my $search       = $client->modeParam('search');

	my @levels       = split(',', $hierarchy);
	my $levelName    = $levels[$level];

	my $playlistMode = Slim::Player::Playlist::playlistMode($client); 

	$log->debug("BrowseAddMenu: levelName=$levelName");

	if ($levelName eq 'track' || $levelName eq 'album') {
		Plugins::PlaylistMan::Plugin::BrowseAddItemMenu($client, $currentItem);
	}
	else {
		$log->debug("$levelName context is not supported at the moment");
	}
}

sub BrowseAddItemMenu
{
	my ($client, $item) = @_;

	my $title = $item->title;
	$log->info("BrowseAddItemMenu for title $title");

	$addItem = $item;

	my %params =
	(
		# The header (first line) to display whilst in this mode.
		header => '{PLUGIN_PLAYLISTMAN_ADD_TO} {count}',

		# A reference to the list of items to display.
		listRef => [
         $client->string('PLUGIN_PLAYLISTMAN_CURRENT_END'),
         $client->string('PLUGIN_PLAYLISTMAN_CURRENT_NEXT'),
			@{$prefs->get('FavouritePlaylists')},
			$client->string('PLUGIN_PLAYLISTMAN_OTHER_PLAYLIST'),
			$client->string('PLUGIN_PLAYLISTMAN_NEW_PLAYLIST')
         ],

		# A unique name for this mode that won't actually get displayed anywhere.
		modeName => PLAYLISTMAN_BROWSE_ADD_MENU,

		parentMode => Slim::Buttons::Common::mode($client),

		selectedItem => $item,

		onPlay => sub {
			my ($client, $action) = @_;
			my $item = $client->modeParam('selectedItem');
			AddItemToAction($client, $action, $item);
		},

		# These are all menu items and so have a right-arrow overlay
		overlayRef => sub {
         my $client = shift; 
         return [ undef, $client->symbols('rightarrow') ];
      }
	);

	$params{onAdd} = $params{onPlay};
	$params{onRight} = $params{onPlay};

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

sub NowPlayingAddAction
{
	my ($client, $action, $item) = @_;

	my $tracktitle = $item->title;

   $log->info("Now Playing Add Action: $action for $tracktitle");

	if ($action eq $client->string('PLUGIN_PLAYLISTMAN_ADD_TRACK_TO'))
	{
		my %params =
		(
			# The header (first line) to display whilst in this mode.
			header => '{PLUGIN_PLAYLISTMAN_ADD_TRACK_TO_PLAYLIST} {count}',

			# A reference to the list of items to display.
			listRef => [@{$prefs->get('FavouritePlaylists')},
                     $client->string('PLUGIN_PLAYLISTMAN_OTHER_PLAYLIST'),
                     $client->string('PLUGIN_PLAYLISTMAN_NEW_PLAYLIST')],

			# A unique name for this mode that won't actually get displayed anywhere.
			modeName => PLAYLISTMAN_MENU_ADD,

			parentMode => Slim::Buttons::Common::mode($client),

			selectedItem => $item,

			onPlay => sub {
				my ($client, $action) = @_;
				my $item = $client->modeParam('selectedItem');
				AddItemToAction($client, $action, $item);
			},

			# These are all menu items and so have a right-arrow overlay
			overlayRef => sub {
            my $client = shift; 
            return [ undef, $client->symbols('rightarrow') ];
         }
		);

		$params{onAdd} = $params{onPlay};
		$params{onRight} = $params{onPlay};

		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
	}
	elsif ($action eq $client->string('PLUGIN_PLAYLISTMAN_ZAP_TRACK'))
	{
		$client->showBriefly(
         { 'line1' => $client->string('ZAPPING_FROM_PLAYLIST'),
           'line2' => Slim::Music::Info::standardTitle($client, $item)
         }
      );

		$client->execute(["playlist", "zap", $playlistindex]);
 		Slim::Buttons::Common::popModeRight($client);
	}
	elsif ($action eq $client->string('PLUGIN_PLAYLISTMAN_SAVE_NEW_PLAYLIST'))
	{
		my $serverPrefs = preferences('server');
		if (!$serverPrefs->get('playlistdir'))
		{
		   my $errormsg = $client->string('NO_PLAYLIST_DIR');
         $log->error($errormsg);
			$client->showBriefly(
            { 'line1' => $client->string('PLUGIN_PLAYLISTMAN_NAME'),
              'line2' => $errormsg
            }
         );
      }
		else
		{
			$context{$client} = $client->currentPlaylist ? Slim::Music::Info::standardTitle($client, $client->currentPlaylist) : 'A';
			Slim::Buttons::Common::pushModeLeft($client, 'SavePlaylist');
		}
	}
}

sub AddItemToAction
{
	my ($client, $action, $item) = @_;

	my $title = $item->title;

   $log->info("Add item $title to $action");

	if ($action eq $client->string('PLUGIN_PLAYLISTMAN_CURRENT_NEXT'))
	{
		$client->showBriefly(
         { 'line1' => $client->string('PLUGIN_PLAYLISTMAN_ADDING_TO_PLAYLIST', 'current')
         }
      );

		my $class = blessed($item);
		if ($class eq 'Slim::Schema::Track') {
			$client->execute(["playlistcontrol", "cmd:insert", "track_id:" . $item->id]);
		}
		elsif ($class eq 'Slim::Schema::Album') {
			$client->execute(["playlistcontrol", "cmd:insert", "album_id:" . $item->id]);
		}
		ExitPlaylistManMenus($client);
	}
	elsif ($action eq $client->string('PLUGIN_PLAYLISTMAN_CURRENT_END'))
	{
		$client->showBriefly(
         { 'line1' => $client->string('PLUGIN_PLAYLISTMAN_ADDING_TO_PLAYLIST', 'current')
         }
      );

		my $class = blessed($item);
		if ($class eq 'Slim::Schema::Track') {
			$client->execute(["playlistcontrol", "cmd:add", "track_id:" . $item->id]);
		}
		elsif ($class eq 'Slim::Schema::Album') {
			$client->execute(["playlistcontrol", "cmd:add", "album_id:" . $item->id]);
		}
		ExitPlaylistManMenus($client);
	}
	elsif ($action eq $client->string('PLUGIN_PLAYLISTMAN_OTHER_PLAYLIST'))
	{
		SelectPlaylistToAddTo($client, $item);
	}
	elsif ($action eq $client->string('PLUGIN_PLAYLISTMAN_NEW_PLAYLIST'))
	{
		Slim::Buttons::Common::pushModeLeft($client, 'NewPlaylist');
	}
	else
	{
		#assume the action is the name of a playlist
		AddItemTo($client, $action, $item);
		ExitPlaylistManMenus($client);
	}
}

sub ExitPlaylistManMenus
{
	my $client = shift;

	if ($client->modeParam('parentMode') eq 'INPUT.Choice') {
		Slim::Buttons::Common::popMode($client);
	}

	Slim::Buttons::Common::popModeRight($client);
}

sub ListOtherPlaylists
{
	my @dirItems=();
	my $playlists = Slim::Schema->rs('Playlist')->getPlaylists;
	my $playlistsCount = 0;

	while (my $playlistObj = $playlists->next)
	{
		my $title = $playlistObj->title;
		$log->info("PlaylistMan: Found playlistname=$title");

		#TODO: Remove configured common playlists from the list of selectable playlists?
		push @dirItems, $title;

		$playlistsCount = $playlistsCount+1;
	}

	$log->info("Found $playlistsCount playlists");
	
	return @dirItems;
}

sub SelectPlaylistToAddTo
{
	my $client = shift;
	my $item = shift;

   $log->info("SelectPlaylistToAddTo");

	my @dirItems=ListOtherPlaylists();

	if (@dirItems > 0)
	{
		my %params =
		(
			# The header (first line) to display whilst in this mode.
			# Handle large Font setting
			header => '{PLUGIN_PLAYLISTMAN_ADD_TO_OTHER_PLAYLIST} {count}',
			listRef => \@dirItems,
			stringHeader => 1,

			# A unique name for this mode that won't actually get displayed anywhere.
			modeName => PLAYLISTMAN_SELECT_OTHER_PLAYLIST,
			parentMode => Slim::Buttons::Common::mode($client),

			selectedItem => $item,
			
			onPlay => sub {
					my ($client, $playlist) = @_;
					my $item = $client->modeParam('selectedItem');
					AddItemTo($client, $playlist, $item);
					Slim::Buttons::Common::popMode($client);
					ExitPlaylistManMenus($client);
				},

			# These are all menu items and so have a right-arrow overlay
			overlayRef => 
				sub {
               my $client = shift;
               return [ undef, $client->symbols('rightarrow') ];
            }
      );

		$params{onAdd} = $params{onPlay};
		$params{onRight} = $params{onPlay};

		Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
	}
	else
	{
		$client->showBriefly({ 'line1' => $client->string('PLUGIN_PLAYLISTMAN_NO_PLAYLISTS')});
	}
}

sub AddItemTo
{
	my ($client, $playlist, $item) = @_;

	$log->debug("AddItemTo: playlist=$playlist, item=$item");

	$client->showBriefly({'line1' => $client->string('PLUGIN_PLAYLISTMAN_ADDING_TO_PLAYLIST', $playlist), 'line2' => Slim::Music::Info::standardTitle($client, $item)});
	AddToPlaylist($client, $playlist, $item);
}

sub AddToPlaylist
{
	my ($client, $playlist, $item) = @_;

	$log->info("Playlist name is: $playlist");

	my $playlistTitle = Slim::Music::Info::plainTitle($playlist, undef);

	$log->info("Playlist plaintitle is: '$playlistTitle'");

   my $serverPrefs = preferences('server');
	my $fileurl = Slim::Utils::Misc::fileURLFromPath(catfile($serverPrefs->get('playlistdir') . '/' . Encode::encode("utf8", $playlist) . '.m3u'));

	$log->info("fileurl=$fileurl");

	my $playlistObj = Slim::Schema->rs('Playlist')->updateOrCreate({
		'url' => $fileurl,
		'playlist' => $playlist,
		'attributes' => {
			'TITLE' => $playlistTitle,
			'CT'    => 'ssp',
		},
	});

	my $class = blessed($item);
	$log->debug("item is $class");

	if ($class eq 'Slim::Schema::Track') {
		$playlistObj->appendTracks([ $item ]);
	} elsif ($class eq 'Slim::Schema::Album') {
		my $tracks = Slim::Schema->rs('Track')->search( {'album' => $item->id }, {'order_by' => 'disc, tracknum, titlesort' });
		my @storeTracks = ();

		$log->debug("found " . $tracks->count . " tracks");
		while (my $track = $tracks->next) {
			$log->debug("track " . $track);
			push @storeTracks, $track; 
		}
		$playlistObj->appendTracks(\@storeTracks);
	} elsif ($class eq 'Slim::Schema::RemoteTrack') {
		$log->debug("Append Remote Track to playlist");
		$playlistObj->appendTracks([ $item ]);
	} elsif ($class eq 'Slim::Schema::RemotePlaylist') {
		$log->debug("Append Remote Playlist to playlist");
		$playlistObj->appendTracks([ $item->url ]);
# 		for my $track ( $item->tracks ) {
# 			$log->debug("track " . $track->name . " url " . $track->url);
# 			$playlistObj->appendTracks([ $track ]);
# 		}
	} else {
		$log->debug("Append $class to playlist");
		$playlistObj->appendTracks([ $item ]);
	}

	Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);
}

sub getFunctions
{
	return \%functions;
}


#Add to new playlist functionality

sub SetNewPlaylistMode
{
	my ($client, $push) = @_;

	$log->info("Display New Playlist menu");

	$client->lines(\&NewPlaylistLines);

   my $serverPrefs = preferences('server');
	if (!$serverPrefs->get('playlistdir'))
	{
	   my $errormsg = $client->string('NO_PLAYLIST_DIR');
      $log->error($errormsg);
		$client->showBriefly(
         { 'line1' => $client->string('PLUGIN_PLAYLISTMAN_NAME'),
           'line2' => $errormsg
         }
      );
	}
	elsif ($push ne 'push')
	{
		#my $playlist = '';
	}
	elsif ($client->modeParam('playlist') ne '')
   {
   	# don't do anything if we have a playlist name, since this
		# means we've done the text entry
   }
   else
	{
		# default to the existing title for a known playlist, otherwise just start with 'A'
		$context{$client} = $client->currentPlaylist ? Slim::Music::Info::standardTitle($client, $client->currentPlaylist) : 'A';

		Slim::Buttons::Common::pushMode($client,'INPUT.Text', {
			'callback' => \&Plugins::PlaylistMan::Plugin::NewPlaylistCallback,
			'valueRef' => \$context{$client},
			'charsRef' => \@LegalChars,
			'numberLetterRef' => \@legalMixed,
			'header' => $client->string('PLUGIN_PLAYLISTMAN_NEW_PLAYLIST'),
			'cursorPos' => 0
		});
	}
}

sub NewPlaylistLines
{
	my $client = shift;

	my ($line1, $line2, $arrow);

	$line1 = $client->string('PLUGIN_PLAYLISTMAN_ADD_TO_NEW_PLAYLIST');
	$line2 = $context{$client};
	$arrow = $client->symbols('rightarrow');

	return
	{
		'line'   => [ $line1, $line2 ], 
		'overlay' => [ undef, $arrow ]
	};
}

our %NewPlaylistFunctions = (
	'left' => sub  {
		my $client = shift;
      $log->info("NewPlaylistFunctions - left");
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		my $playlistfile = $context{$client};

      $log->info("NewPlaylistFunctions - right");

		NewPlaylist($client, $playlistfile);
		Slim::Buttons::Common::popMode($client);
		Slim::Buttons::Common::popMode($client);
		Slim::Buttons::Common::popMode($client);
		ExitPlaylistManMenus($client);
	},
	'save' => sub {
		my $client = shift;
      $log->info("NewPlaylistFunctions - save");
		Slim::Buttons::Common::pushModeLeft($client, 'NewPlaylist');
	},
);

sub GetNewPlaylistFunctions
{
	return \%NewPlaylistFunctions;
}

sub NewPlaylist
{
	my ($client, $playlist) = @_;

	$log->info("Add to new playlist $playlist");

	AddToPlaylist($client, $playlist, $addItem);

	$log->debug("Added to new playlist");

	$client->showBriefly( {
		'line1' => $client->string('PLAYLIST_SAVING'),
		'line2' => $playlist
	});
}

sub NewPlaylistCallback
{
	my ($client, $type) = @_;

   $log->info("NewPlaylistCallback $type");

	if ($type eq 'nextChar')
   {
		# re-enter plugin with the new playlist title to get the confirmation screen for saving the playlist.
		Slim::Buttons::Common::pushModeLeft($client, 'NewPlaylist', { 'playlist' => $context{$client} });
	}
   elsif ($type eq 'backspace')
   {
   	Slim::Buttons::Common::popModeRight($client);
		Slim::Buttons::Common::popModeRight($client);
	}
   else
   {
		$client->bumpRight();
	}
}


#Save Playlist functionality

sub SetSavePlaylistMode
{
	my ($client, $push) = @_;

	$client->lines(\&SavePlaylistLines);

   my $serverPrefs = preferences('server');
	if (!$serverPrefs->get('playlistdir'))
	{
	   my $errormsg = $client->string('NO_PLAYLIST_DIR');
      $log->error($errormsg);
		$client->showBriefly(
         { 'line1' => $client->string('PLUGIN_PLAYLISTMAN_NAME'),
           'line2' => $errormsg
         }
      );
	}
	elsif ($push ne 'push')
	{
		# my $playlist = '';
	}
	elsif ($client->modeParam('playlist') ne '')
   {
   	# don't do anything if we have a playlist name, since this
		# means we've done the text entry
   }
	else
	{
		$context{$client} = $client->currentPlaylist ? Slim::Music::Info::standardTitle($client, $client->currentPlaylist) : 'A';

		# set cursor position to end of playlist title if the playlist is known
		my $cursorpos = $client->currentPlaylist ?  length($context{$client}) : 0;

		Slim::Buttons::Common::pushMode($client,'INPUT.Text', {
			'callback' => \&Plugins::PlaylistMan::Plugin::SavePlaylistCallback,
			'valueRef' => \$context{$client},
			'charsRef' => \@LegalChars,
			'numberLetterRef' => \@legalMixed,
			'header' => $client->string('PLAYLIST_AS'),
			'cursorPos' => $cursorpos
		});
	}
}

sub SavePlaylistLines
{
	my $client = shift;

	my ($line1, $line2, $arrow);

   my $serverPrefs = preferences('server');
   my $playlistdir = $serverPrefs->get('playlistdir');
	if (!$playlistdir)
	{
	   my $errormsg = $client->string('NO_PLAYLIST_DIR');
      $log->error($errormsg);

		$line1 = $client->string('NO_PLAYLIST_DIR');
		$line2 = $client->string('NO_PLAYLIST_DIR_MORE');
	}
   else
   {
   	my $newUrl = Slim::Utils::Misc::fileURLFromPath(catfile($playlistdir) . '/' . $context{$client} . '.m3u');
      $log->info("New playlist URL is $newUrl");

      if (Slim::Schema->rs('Track')->objectForUrl($newUrl))
      {
   		# Special text for overwriting an existing playlist
   		# if large text, make sure we show the message instead of the playlist name
   		if ($client->linesPerScreen == 1) {
   			$line2 = $client->doubleString('PLAYLIST_OVERWRITE');
   		} else {
   			$line1 = $client->string('PLAYLIST_OVERWRITE');
   			$line2 = $context{$client};
   		}
   		
   		$arrow = $client->symbols('rightarrow');
   	}
   	else
   	{
   		$line1 = $client->string('PLUGIN_PLAYLISTMAN_SAVE_NEW_PLAYLIST_CONFIRM');
   		$line2 = $context{$client};
   		$arrow = $client->symbols('rightarrow');
   	}
   }

	return
	{
		'line1'   => $line1,
		'line2'   => $line2, 
		'overlay' => [ undef, $arrow ]
	};
}

our %SavePlaylistFunctions = (
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;
		my $playlistfile = $context{$client};
		SavePlaylist($client, $playlistfile);
		Slim::Buttons::Common::popMode($client);
		Slim::Buttons::Common::popMode($client);
		Slim::Buttons::Common::popMode($client);
		Slim::Buttons::Common::popModeRight($client);
	},
	'save' => sub {
		my $client = shift;
		Slim::Buttons::Common::pushModeLeft($client, 'SavePlaylist');
	},
);

sub GetSavePlaylistFunctions
{
	return \%SavePlaylistFunctions;
}

sub SavePlaylist
{
	my $client = shift;
	my $playlistfile = shift;

	$client->execute(['playlist', 'save', $playlistfile]);
	$client->showBriefly( {
		'line1' => $client->string('PLAYLIST_SAVING'),
		'line2' => $playlistfile
	});
}

sub SavePlaylistCallback
{
	my ($client, $type) = @_;

	if ($type eq 'nextChar')
   {
		# re-enter plugin with the new playlist title to get the confirmation screen for saving the playlist.
		Slim::Buttons::Common::pushModeLeft($client, 'SavePlaylist', { 'playlist' => $context{$client}, });
	}
   elsif ($type eq 'backspace')
   {
   	Slim::Buttons::Common::popModeRight($client);
		Slim::Buttons::Common::popModeRight($client);
	}
   else
   {
		$client->bumpRight();
	}
}

# Adds a mapping for 'addmenu' function in Now Playing mode.
our %mapping = (
	'add.single' => 'addmenu',
	'add.hold' => 'add'
);

sub defaultMap
{
	return \%mapping; 
}

sub initPlugin
{
	my $class = shift;

	$VERSION = $class->_pluginDataFor('version');

	$log->info("Initialising " . Slim::Utils::Strings::string('PLUGIN_PLAYLISTMAN_NAME') . " version $VERSION");

	Slim::Buttons::Common::addMode(PLAYLISTMAN_BROWSE_ADD_MENU, {}, \&Plugins::PlaylistMan::Plugin::ItemInfoAddMenu);
	Slim::Buttons::Common::addMode('SavePlaylist', GetSavePlaylistFunctions(), \&Plugins::PlaylistMan::Plugin::SetSavePlaylistMode);
	Slim::Buttons::Common::addMode('NewPlaylist', GetNewPlaylistFunctions(), \&Plugins::PlaylistMan::Plugin::SetNewPlaylistMode);

	Slim::Hardware::IR::addModeDefaultMapping('playlist', \%mapping);

	# Classic SB Player UI IR shortcut to display options when Add key is pressed in Now Playling list
	Slim::Buttons::Playlist::getFunctions()->{'addmenu'} = $functions{'addmenu'};

	if ($::VERSION lt '7.6') {
		# For pre-SBS 7.6, support a mode that can be entered when browsing any item.
		# i.e. for binding to a key in an IR Map.
		
		# SBS 7.6 doesn't support this - user can use the context menu instead
		Slim::Buttons::BrowseDB::getFunctions()->{'BrowseAddMenu'} = \&Plugins::PlaylistMan::Plugin::BrowseAddMenu;
		#Slim::Buttons::XMLBrowser::getFunctions()->{'BrowseAddMenu'} = \&Plugins::PlaylistMan::Plugin::BrowseAddMenu;
	}

	# requires Client
	# is a Query
	# has Tags
	# Function to call
	Slim::Control::Request::addDispatch(['playlistman','add','track'], [1, 0, 1, \&cliAddToHandler]);
	Slim::Control::Request::addDispatch(['playlistman','add','album'], [1, 0, 1, \&cliAddToHandler]);

	if ($::VERSION ge '7.1') {
		Slim::Menu::TrackInfo->registerInfoProvider( addTo => (
			before => 'top',
			func => \&trackInfoHandler,
		) );

		Slim::Menu::AlbumInfo->registerInfoProvider( addTo => (
				before => 'top',
				func => \&albumInfoHandler,
		) );
	}

	Plugins::PlaylistMan::Settings->new;
}
