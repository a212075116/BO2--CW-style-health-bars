// ============================================================================
//  Zh_HealthBars  (T6 zombies)  --  fully standalone "injection" gametype.
//  COD17-style zombie health bars + floating damage numbers, self-contained.
//  Treat main.gsc as ABSENT: this file is its own gametype (init/main) and holds
//  every bite of the health-bar logic, including the damage capture callback.
//
//  The LUI half lives in storage\t6\ui_mp\t6\hud.lua and
//  storage\t6\ui_mp\t6\zombie\zombiehealthbars.lua (hot-reloaded separately).
//
//  DATA FLOW -> LUI
//    * zh_data_0..N   "entityNum:ratio100:alpha100:name;..."  (batched client dvars)
//    * zh_dmg          "entityNum:amount:seq:distance;..."      (damage events)
// ============================================================================

#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\gametypes_zm\_spawnlogic;
#include maps\mp\animscripts\traverse\shared;
#include maps\mp\animscripts\utility;
#include maps\mp\zombies\_load;
#include maps\mp\_createfx;
#include maps\mp\_music;
#include maps\mp\_busing;
#include maps\mp\_script_gen;
#include maps\mp\gametypes_zm\_globallogic_audio;
#include maps\mp\gametypes_zm\_tweakables;
#include maps\mp\_challenges;
#include maps\mp\gametypes_zm\_weapons;
#include maps\mp\_demo;
#include maps\mp\gametypes_zm\_spawning;
#include maps\mp\gametypes_zm\_globallogic_utils;
#include maps\mp\gametypes_zm\_spectating;
#include maps\mp\gametypes_zm\_globallogic_spawn;
#include maps\mp\gametypes_zm\_globallogic_ui;
#include maps\mp\gametypes_zm\_hostmigration;
#include maps\mp\gametypes_zm\_globallogic_score;
#include maps\mp\gametypes_zm\_globallogic;
#include maps\mp\zombies\_zm;
#include maps\mp\zombies\_zm_ai_faller;
#include maps\mp\zombies\_zm_spawner;
#include maps\mp\zombies\_zm_pers_upgrades_functions;
#include maps\mp\zombies\_zm_pers_upgrades;
#include maps\mp\zombies\_zm_score;
#include maps\mp\animscripts\zm_run;
#include maps\mp\animscripts\zm_death;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\animscripts\zm_shared;
#include maps\mp\animscripts\zm_utility;
#include maps\mp\zombies\_zm_ai_basic;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_net;
#include maps\mp\zombies\_zm_audio;
#include maps\mp\gametypes_zm\_zm_gametype;
#include maps\mp\_visionset_mgr;
#include maps\mp\zombies\_zm_equipment;
#include maps\mp\zombies\_zm_server_throttle;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\zombies\_zm_unitrigger;
#include maps\mp\zombies\_zm_zonemgr;
#include maps\mp\zombies\_zm_perks;
#include maps\mp\zombies\_zm_melee_weapon;
#include maps\mp\zombies\_zm_audio_announcer;
#include maps\mp\zombies\_zm_magicbox;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_power;
#include maps\mp\zombies\_zm_ai_dogs;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_game_module;
#include maps\mp\zombies\_zm_buildables;
#include codescripts\character;
#include maps\mp\zombies\_zm_weap_riotshield;
#include maps\mp\zombies\_zm_ai_sloth;
#include maps\mp\zombies\_zm_ai_sloth_ffotd;
#include maps\mp\zombies\_zm_ai_sloth_utility;
#include maps\mp\zombies\_zm_ai_sloth_magicbox;
#include maps\mp\zombies\_zm_ai_sloth_crawler;
#include maps\mp\zombies\_zm_ai_sloth_buildables;
#include maps\mp\zm_transit_lava;

main()
{
	// This is a health-bars-only gametype; no replaceFunc customisation needed.
	// The base zombie mode is driven by the included scripts / the map's own code.
}

init()
{
	println( "ZH_HEALTHBARS: init ran" );
	level thread onPlayerConnect();
	level thread onPlayerDisConnect();

	// ---- zombie health bars (server side) ----
	// Track freshly-dead zombies so their bars drain away.
	level.zh_dead = [];
	register_zombie_death_event_callback( ::zh_mark_dead );

	// Damage capture for floating numbers: hook the actor-damage callback (self =
	// the damaged zombie, attacker = the shooting player). This stays self-contained
	// here so the system does NOT depend on any other gametype script.
    level thread keep_damage_override();
}

keep_damage_override()
{
	while(1)
	{
		level.callbackActorDamage = ::_actor_damage_override_wrapper;
		wait 1;
	}
}

onPlayerConnect()
{
	for(;;)
	{
		level waittill( "connected", player );
		player thread onPlayerSpawned();
	}
}

onPlayerDisConnect()
{
	for(;;)
	{
		level waittill( "disconnect", player );
		player thread onPlayerDisConnected();
	}
}

onPlayerDisConnected()
{
	self endon( "disconnect" );
}

onPlayerSpawned()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	while( 1 )
	{
		self waittill( "spawned_player" );
		waittillframeend;
		self thread zombie_lui_push();
		self thread zh_damage_hud();
	}
}

zh_mark_dead()
{
	level.zh_dead[ self getentitynumber() ] = gettime();
}

// Delete a (short-lived) damage-number anchor after its number is long gone.
zh_delete_anchor()
{
	wait 2.5;
	if( isDefined( self ) )
		self delete();
}

// Damage-number capture.  Runs as level.callbackActorDamage: self = the damaged
// zombie, attacker = the player who dealt it, damage = actual damage dealt. We
// pin the number to a STATIC anchor spawned AT the hit position so it does NOT
// ride the zombie (spawn() at the position, not setorigin, which would not move).
_actor_damage_override_wrapper( inflictor, attacker, damage, flags, meansofdeath, weapon, vpoint, vdir, shitloc, psoffsettime, boneindex )
{
	if( !isDefined( attacker ) || !IsPlayer( attacker ) || !isDefined( damage ) )
		return damage;

	dmgDist = 0;
	if( isDefined( attacker.origin ) && isDefined( self.origin ) )
		dmgDist = int( Distance( attacker.origin, self.origin ) );

	if( !isDefined( attacker.zh_dmgSeq ) )
		attacker.zh_dmgSeq = 0;
	attacker.zh_dmgSeq = attacker.zh_dmgSeq + 1;

	if( !isDefined( attacker.zh_dmgList ) )
	{
		attacker.zh_dmgList = [];
		attacker.zh_dmgTimes = [];
	}

	if( isDefined( self.origin ) )
	{
		anchor = spawn( "script_model", self.origin );
		anchor thread zh_delete_anchor();
		dmgEnt = anchor getentitynumber();
	}
	else
	{
		dmgEnt = self getentitynumber();
	}

	attacker.zh_dmgList[ attacker.zh_dmgList.size ] = dmgEnt + ":" + int( damage + 0.5 ) + ":" + attacker.zh_dmgSeq + ":" + dmgDist;
	attacker.zh_dmgTimes[ attacker.zh_dmgTimes.size ] = gettime();

	actor_damage_override_wrapper(inflictor, attacker, damage, flags, meansofdeath, weapon, vpoint, vdir, shitloc, psoffsettime, boneindex);
}

// Push zombie health-bar data to this player's LUI via client dvar(s).
// Per zombie: "entityNum:ratio100:alpha100:name" (batched across zh_data_0..N).
// LUI polls the dvars every ~100ms and follows each zombie by entity number.
zombie_lui_push()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	// Only ever run ONE push thread per player.
	if ( isDefined( self.zh_pushing ) )
		return;
	self.zh_pushing = 1;

	wait 3;    // let the round start / zombies spawn

	// Batch the health-bar payload across several client dvars (zh_data_0..N).
	// A single dvar was too long with many zombies and got truncated, dropping the
	// tail. Keep each dvar small (BATCH zombies) so nothing is cut.
	zh_batch = 10;
	zh_dvars = 8;

	while ( 1 )
	{
		strArr = [];
		cur = "";
		curCount = 0;
		// player aim direction (for "crosshair on a zombie reveals its bar") —
		// guard getplayerangles; it can be undefined in some states and would
		// otherwise crash anglestoforward/vectornormalize.
		aimForward = undefined;
		pa = self getplayerangles();
		if ( isDefined( pa ) )
			aimForward = vectornormalize( anglestoforward( pa ) );
		// The LOS trace must start at the player's EYES, not their feet, or the
		// ground / low cover would wrongly block it. geteye() is a real T6 call
		// (used by stock zm_dog_combat.gsc); fall back to origin + eye height.
		eyePos = self geteye();
		if ( !isDefined( eyePos ) )
			eyePos = self.origin + ( 0, 0, 60 );
		zombies = GetAIArray( level.zombie_team );
		dogs = getentarray( "zombie_dog", "targetname" );
		for ( p = 0; p < ( zombies.size + dogs.size ); p++ )
		{
			if ( p < zombies.size )
				z = zombies[p];
			else
				z = dogs[ p - zombies.size ];

			if ( !isDefined( z ) )
				continue;
			// Hellhounds are NOT in level.zombie_team, so they're pulled separately
			// above via the "zombie_dog" targetname. They still have health/origin,
			// so the checks below handle them.

			entNum = z getentitynumber();
			dying = 0;
			// isAlive is authoritative for "is this a live bar". Entity numbers are
			// recycled by the game, so a fresh spawn can reuse a number whose old
			// zombie died. If this entity is alive, clear any stale death marker so
			// the recycled/new zombie is NOT skipped (the old kill must not hide it).
			if ( isAlive( z ) )
			{
				level.zh_dead[entNum] = undefined;
				if ( !isDefined( z.health ) || z.health <= 0 )
					continue;
			}
			else if ( isDefined( level.zh_dead[entNum] ) )
			{
				dElapsed = gettime() - level.zh_dead[entNum];
				if ( dElapsed >= 600 )
				{
					level.zh_dead[entNum] = undefined;   // drain finished -> drop the bar
					continue;
				}
				dying = 1;      // keep it for the 0.6s drain
			}
			else
			{
				continue;       // dead and not a recent registered death -> skip
			}

			d = Distance( self.origin, z.origin );
			alpha = 0;
			// Trace runs from the player's EYES to the zombie's chest/head height,
			// so the ground and low cover don't wrongly block a visible zombie.
			// bullettracepassed returns true when nothing solid is between the two
			// points (0 = don't test characters, self = ignore the player).
			if ( d <= 260 )
			{
				if ( bullettracepassed( eyePos, ( z.origin + ( 0, 0, 40 ) ), 0, self ) )
				{
					if ( d <= 100 )
						alpha = 0.85;
					else
						alpha = 0.85 * ( 260 - d ) / ( 260 - 100 );
				}
			}
			// NOTE: we keep sending ALL alive zombies (even far ones, alpha = 0)
			// so the LUI keeps their bar "in place" (invisible) instead of dropping
			// it. This way only truly DEAD zombies trigger the drain-to-zero.

			// crosshair on this zombie?  reveal it even at long range, but ONLY if
			// we actually have line of sight (a wall in between blocks it).
			aimed = 0;
			if ( isDefined( aimForward ) && isDefined( eyePos ) && d > 1 && isDefined( z.origin ) )
			{
				// Aim at the zombie's chest height, straight from the eye, so the dot
				// matches the line the player is actually looking down.
				toZN = vectornormalize( ( z.origin + ( 0, 0, 40 ) ) - eyePos );
				dot = vectordot( aimForward, toZN );
				if ( dot > 0.99 && bullettracepassed( eyePos, ( z.origin + ( 0, 0, 40 ) ), 0, self ) )
					aimed = 1;
			}
			if ( aimed && d <= 900 )
				alpha = 0.85;   // aimed zombie always shown (full-ish)

			ratio = 1;
			if ( isDefined( z.maxhealth ) && z.maxhealth > 0 )
				ratio = z.health / z.maxhealth;

			if ( dying )
			{
				// decay the ratio to 0 over the drain window so the bar
				// visibly drains to zero, then disappears.
				ratio = ratio * max( 0, 1 - dElapsed / 600 );
				if ( alpha <= 0 )
					alpha = 0.3;   // keep it faintly visible while draining
			}
			ratio = max( 0, min( ratio, 1 ) );

			// Display name depends on the entity type (zombie vs hellhound). isdog
			// is the same flag the mod's own scripts use to tell them apart.
			zname = "ZOMBIE";
			if ( isDefined( z.isdog ) && z.isdog )
				zname = "HELLHOUND";

			// entNum:ratio:alpha:name (no ':' or ';' in any field)
			if ( cur != "" )
				cur = cur + ";";
			cur = cur + entNum + ":" + int( ratio * 100 + 0.5 ) + ":" + int( alpha * 100 + 0.5 ) + ":" + zname;
			curCount = curCount + 1;
			if ( curCount >= zh_batch )
			{
				strArr[ strArr.size ] = cur;
				cur = "";
				curCount = 0;
			}
		}

		if ( cur != "" )
			strArr[ strArr.size ] = cur;

		// Write each batch to its own client dvar so no single dvar gets too long.
		// (Many zombies used to truncate zh_data and drop the last few bars.)
		for ( bi = 0; bi < zh_dvars; bi++ )
		{
			if ( bi < strArr.size )
				self setclientdvar( "zh_data_" + bi, strArr[bi] );
			else
				self setclientdvar( "zh_data_" + bi, "" );
		}
		wait 0.1;
	}
}

// Flush this player's damage-number events to a client dvar for the LUI. Each
// event is "entNum:amount:seq:distance" and is retained ~0.3s (the LUI dedupes by
// seq), so even a killing blow shows a number even though the zombie left the array.
zh_damage_hud()
{
	self endon( "disconnect" );
	level endon( "game_ended" );

	while( 1 )
	{
		if( !isDefined( self.zh_dmgList ) )
		{
			self.zh_dmgList = [];
			self.zh_dmgTimes = [];
		}
		now = gettime();
		newList = [];
		newTimes = [];
		dmgStr = "";
		fd = 1;
		for( i = 0; i < self.zh_dmgList.size; i++ )
		{
			if( now - self.zh_dmgTimes[i] <= 300 )
			{
				if( fd )
					fd = 0;
				else
					dmgStr = dmgStr + ";";
				dmgStr = dmgStr + self.zh_dmgList[i];
				newList[ newList.size ] = self.zh_dmgList[i];
				newTimes[ newTimes.size ] = self.zh_dmgTimes[i];
			}
		}
		self.zh_dmgList = newList;
		self.zh_dmgTimes = newTimes;
		self setclientdvar( "zh_dmg", dmgStr );
		wait 0.05;
	}
}
