// ============================================================================
//  Zh_HealthBars  (T6 zombies)  --  fully standalone "injection" gametype.
//  COD17-style zombie health bars + floating damage numbers, self-contained.
//
//  The LUI half lives in storage\t6\ui_mp\t6\hud.lua and
//  storage\t6\ui_mp\t6\zombie\zombiehealthbars.lua (hot-reloaded separately).
//
//  DATA FLOW -> LUI
//    * zh_data_0..N   "entityNum:ratio100:alpha100:name;..."  (batched client dvars)
//    * zh_dmg          "entityNum:amount:seq:distance;..."      (damage events)
//
//  NOTE ON DAMAGE CAPTURE (bugfix): we deliberately do NOT touch the engine's
//  single-slot "level.callbackActorDamage" any more. That slot was being grabbed
//  every 1s by BOTH this script AND main.gsc's own keep_damage_override(), so the
//  two overwrote each other and whichever loop did NOT own the slot at hit-time
//  silently dropped its events -> "some zombies fire no damage number". The
//  single slot now belongs to main.gsc (weapon multipliers). Damage numbers are
//  captured here via the ARRAY-based zombie_damage callback list instead, which
//  supports many independent registrants (register_zombie_damage_callback), so it
//  can never collide with anything else. The "amount" delivered on that path is
//  the FINAL, post-multiplier damage -> the popup now matches the bar drain.
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
	level thread onPlayerConnect();
	level thread onPlayerDisConnect();

	// ---- zombie health bars (server side) ----
	// Register the animname probe dvar so it exists (and tab-completes in the
	// console) from map load. 0 = OFF, the normal playing state; `setdvar
	// zh_animname 1` switches the raw-animname label probe on.
	setdvar( "zh_animname", "0" );

	// Track freshly-dead zombies so their bars drain away.
	level.zh_dead = [];
	register_zombie_death_event_callback( ::zh_mark_dead );

	// Damage capture for floating numbers. Non-killing hits DO reach the ARRAY
	// zombie_damage callback list (many registrants coexist -> never fights
	// main.gsc's single-slot callbackActorDamage). self = the damaged zombie,
	// player = attacker, amount = the FINAL post-multiplier damage dealt.
	register_zombie_damage_callback( ::zh_actor_damage_hook );

	// The KILLING blow is dropped by vanilla _zm_spawner::enemy_death_detection
	// (its `if(!isalive(self)) return;` gate fires BEFORE zombie_damage), so the
	// array hook never sees a one-shot kill -> those zombies fire NO number. We
	// catch it on the engine's actor-KILLED path instead: _zm::actor_killed_override
	// forwards to a PER-ENTITY self.actor_killed_override slot (_zm.gsc:4525-4526),
	// where idamage is the real post-multiplier killing damage. zh_watch_all() tags
	// every zombie AND dog (dogs skip zombie_spawn_init, so polling BOTH by
	// targetname is required) with ::zh_killed_hook. This grabs NO level.* singleton
	// -> never fights main.gsc's callbackActorDamage; and the killing blow never
	// reaches the array hook, so the two popups are mutually exclusive per hit.
	level thread zh_watch_all();
}

// Poll all zombies + dogs and attach ONE idempotent damage watcher per entity.
// Polling (not the spawn-logic hook) is deliberate: dogs never run
// zombie_spawn_init, so they would otherwise never get watched.
// ---- BO1-style CRAWLER (theater map's gate-crawlers) --------------------------
// The mod's actor-type name for it is not visible on disk (everything is inside
// mod.ff) and EVERY AI entity shares classname "actor" (see the mod's own
// zzz_zm_roundwatch.gsc:43), so guessing one name is unreliable. Instead we probe
// a few plausible targetnames: whichever one hits gets stamped zh_isCrawler, and
// if none hit nothing breaks - those actors simply keep the plain ZOMBIE label.
zh_crawler_names()
{
	names = [];
	names[ names.size ] = "zombie_crawler";
	names[ names.size ] = "sloth_crawler";
	names[ names.size ] = "zombie_sloth_crawler";
	names[ names.size ] = "zm_crawler";
	names[ names.size ] = "crawler";
	return names;
}

zh_crawlers()
{
	out = [];
	names = zh_crawler_names();
	for ( i = 0; i < names.size; i++ )
	{
		found = getentarray( names[i], "targetname" );
		for ( j = 0; j < found.size; j++ )
		{
			if ( !isDefined( found[j] ) )
				continue;
			found[j].zh_isCrawler = 1;
			out[ out.size ] = found[j];
		}
	}
	return out;
}

zh_watch_all()
{
	level endon( "game_ended" );

	for(;;)
	{
		targets = getentarray( "zombie", "targetname" );
		dogs = getentarray( "zombie_dog", "targetname" );
		foreach( dog in dogs )
			targets[ targets.size ] = dog;
		// crawlers too - zh_crawlers() also stamps the zh_isCrawler flag used for
		// the label and the icon colour.
		crawlers = zh_crawlers();
		foreach( c in crawlers )
			targets[ targets.size ] = c;

		foreach( e in targets )
		{
			// _zm's vanilla actor_killed_override forwards to this PER-ENTITY slot
			// (_zm.gsc:4525-4526) on the killing blow. We therefore NEVER grab the
			// level.callbackactorkilled / callbackActorDamage singletons, so we
			// cannot fight main.gsc. idamage there is the post-multiplier value.
			if( isDefined( e ) && isAlive( e ) && !isDefined( e.zh_killedHooked ) )
			{
				e.zh_killedHooked = 1;
				e.actor_killed_override = ::zh_killed_hook;
				zh_attach_head_anchor( e );
			}
		}

		wait 0.05;
	}
}

// Fired by vanilla _zm::actor_killed_override through the PER-ENTITY forward at
// _zm.gsc:4525-4526, with self = the dying zombie/dog. This is the one place the
// engine hands us the KILLING blow's real damage (idamage) while both `attacker`
// (a player) and `self.origin` are still valid. zh_actor_damage_hook NEVER sees
// this blow (its source, enemy_death_detection, bails out at the !isalive gate),
// so the array path and this killed path are mutually exclusive per hit -> no
// duplicate popup, no gap. shitloc here is a hit LOCATION (see is_headshot), NOT
// a coordinate, so zh_killed_hook resolves the point via a 3-tier fallback below.
zh_killed_hook( einflictor, attacker, idamage, smeansofdeath, sweapon, vdir, shitloc, psoffsettime )
{
	if( !isDefined( attacker ) || !IsPlayer( attacker ) )
		return;
	if( attacker == self )
		return;
	if( !isDefined( idamage ) )
		return;

	// Where the killing-blow popup appears. NOTE: self.origin is the zombie's FEET,
	// not its centre, so a bare origin fallback would spawn the number on the floor.
	//  1) reuse the LAST NON-KILLING hit coordinate cached by zh_actor_damage_hook;
	//  2) else the engine's own self.damagehit_origin (best effort: on a pure
	//     one-shot this is usually still undefined, since zombie_damage never ran
	//     for the killing blow, and the killed callback only carries shitloc/vdir,
	//     never a world coordinate);
	//  3) else lift ~45 units above the feet so it reads as the torso.
	anchor = undefined;
	if( isDefined( self.zh_lastHitOrigin ) )
		anchor = self.zh_lastHitOrigin;
	if( !isDefined( anchor ) && isDefined( self.damagehit_origin ) )
		anchor = self.damagehit_origin;
	if( !isDefined( anchor ) && isDefined( self.origin ) )
		anchor = self.origin + ( 0, 0, 45 );

	self zh_fire_number( attacker, idamage, anchor );

	// BOCW-style kill notice, sent to whoever landed the killing blow. shitloc is the
	// killing hit's LOCATION NAME ("head"/"helmet"/"torso_upper"/...), which is exactly
	// what decides whether this reads as a "critical" kill.
	attacker zh_push_kill_notice( smeansofdeath, shitloc );
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

	// Freeze the bar's bone anchor where it is (the drain should stay put rather
	// than ride the death animation) and retire it AFTER the LUI faded the bar.
	if ( isDefined( self.zh_headAnchor ) )
		self.zh_headAnchor thread zh_retire_anchor();
}

// First bone tag on this AI that resolves to a real (non-zero) world point.
// Zombies expose "tag_eye"/"j_head", hellhounds "J_EyeBall_LE"; a model missing
// all of them yields undefined and we keep the old feet-origin behaviour.
zh_head_tag( z )
{
	// NOTE: a GSC "( a, b, c )" literal is a VECTOR, so build a real array here.
	cand = [];
	cand[0] = "tag_eye";
	cand[1] = "j_head";
	cand[2] = "J_EyeBall_LE";
	cand[3] = "tag_head";
	for ( i = 0; i < cand.size; i++ )
	{
		o = z gettagorigin( cand[i] );
		if ( isDefined( o ) && ( o[0] != 0 || o[1] != 0 || o[2] != 0 ) )
			return cand[i];
	}
	return undefined;
}

// Spawn an INVISIBLE script_model, hard-attach it to the zombie's head/eye bone and
// remember its entity number. linkto is resolved by the ENGINE every frame, so the
// LUI just follows this anchor: the bar sits at the eyes with NO per-tick script and
// NO extra dvar payload. (The damage-number anchors already prove a server
// script_model's entity number is valid for setupEntityContainer.)
zh_attach_head_anchor( z )
{
	if ( isDefined( z.zh_headAnchor ) )
		return;

	tag = zh_head_tag( z );
	if ( !isDefined( tag ) )
		return;

	a = spawn( "script_model", z.origin );
	a.zh_entNum = a getentitynumber();
	// Zero world offset: the anchor sits exactly ON the eye/head bone. The bar's
	// clearance is now applied in SCREEN space by the LUI (HEADZ * distance scale).
	// Reason: a world-vertical +Z lift projects to (cos of pitch) on screen, so when
	// the player looks down from high ground the lift collapses back onto the zombie
	// and hides its head. A screen-space lift is immune to camera pitch.
	a linkto( z, tag, ( 0, 0, 0 ), ( 0, 0, 0 ) );
	z.zh_headAnchor = a;
}

// Detach so the bar stops following the corpse, then linger past the LUI fade and
// delete: entity numbers must NOT be recycled while a bar can still reference them.
zh_retire_anchor()
{
	self unlink();
	wait 2;
	if ( isDefined( self ) )
		self delete();
}

// Delete a (short-lived) damage-number anchor after its number is long gone.
zh_delete_anchor()
{
	wait 2.5;
	if( isDefined( self ) )
		self delete();
}

// ---------------------------------------------------------------------------
// BOCW-style kill notices ("+N Zombie Elimination" / "+N Zombie Critical Kill")
//
// The score is NOT guessed: it replays the stock "death" branch of
// _zm_score::player_add_points(), which is
//     get_zombie_death_player_points() + kill_bonus   ->   round_up_score(_, 5)
// then multiplied by get_points_multiplier(player). Those are all stock global
// functions / level.zombie_vars entries, so a mod that rebalances kill scores or
// the point scalar is reflected automatically, with nothing to keep in sync here.
// ---------------------------------------------------------------------------
zh_kill_is_crit( means, hitloc )
{
	// Stock kill_bonus() checks MOD_MELEE / MOD_BURNED BEFORE hit_location, so a
	// melee kill that happens to register on the head is not "critical" either.
	if( means == "MOD_MELEE" || means == "MOD_BURNED" )
		return false;
	if( !isDefined( hitloc ) )
		return false;
	return ( hitloc == "head" || hitloc == "helmet" );
}

zh_kill_bonus( means, hitloc )
{
	// mirrors _zm_score::player_add_points_kill_bonus() (_zm_score.gsc:232-272)
	if( means == "MOD_MELEE" )
		return level.zombie_vars["zombie_score_bonus_melee"];
	if( means == "MOD_BURNED" )
		return level.zombie_vars["zombie_score_bonus_burn"];
	if( !isDefined( hitloc ) )
		return 0;
	if( hitloc == "head" || hitloc == "helmet" )
		return level.zombie_vars["zombie_score_bonus_head"];
	if( hitloc == "neck" )
		return level.zombie_vars["zombie_score_bonus_neck"];
	if( hitloc == "torso_lower" || hitloc == "torso_upper" )
		return level.zombie_vars["zombie_score_bonus_torso"];
	return 0;
}

// self = the killer. Same arithmetic as the engine's own kill payout.
zh_kill_score( means, hitloc )
{
	total = get_zombie_death_player_points() + zh_kill_bonus( means, hitloc );
	return int( get_points_multiplier( self ) * round_up_score( total, 5 ) );
}

// Queue one notice on the killer; zh_damage_hud() flushes the queue to `zh_kill`.
zh_push_kill_notice( means, hitloc )
{
	if( !isDefined( self.zh_killSeq ) )
	{
		self.zh_killSeq = 0;
		self.zh_killList = [];
		self.zh_killTimes = [];
	}
	self.zh_killSeq = self.zh_killSeq + 1;

	crit = 0;
	if( zh_kill_is_crit( means, hitloc ) )
		crit = 1;

	score = self zh_kill_score( means, hitloc );

	self.zh_killList[ self.zh_killList.size ] = self.zh_killSeq + ":" + score + ":" + crit;
	self.zh_killTimes[ self.zh_killTimes.size ] = gettime();
}

// Push ONE floating damage number through the shared channel: an entry in
// player.zh_dmgList that zh_damage_hud() flushes to the `zh_dmg` client dvar.
// self = the zombie (its origin is the fallback anchor point).
zh_fire_number( player, amount, hit_origin )
{
	if( !isDefined( player ) || !IsPlayer( player ) || !isDefined( amount ) )
		return;

	dmgDist = 0;
	if( isDefined( player.origin ) && isDefined( self.origin ) )
		dmgDist = int( Distance( player.origin, self.origin ) );

	if( !isDefined( player.zh_dmgSeq ) )
		player.zh_dmgSeq = 0;
	player.zh_dmgSeq = player.zh_dmgSeq + 1;

	if( !isDefined( player.zh_dmgList ) )
	{
		player.zh_dmgList = [];
		player.zh_dmgTimes = [];
	}

	spawnAt = self.origin;
	if( isDefined( hit_origin ) )
		spawnAt = hit_origin;

	if( isDefined( spawnAt ) )
	{
		anchor = spawn( "script_model", spawnAt );
		anchor thread zh_delete_anchor();
		dmgEnt = anchor getentitynumber();
	}
	else
	{
		dmgEnt = self getentitynumber();
	}

	player.zh_dmgList[ player.zh_dmgList.size ] = dmgEnt + ":" + int( amount + 0.5 ) + ":" + player.zh_dmgSeq + ":" + dmgDist;
	player.zh_dmgTimes[ player.zh_dmgTimes.size ] = gettime();
}

// Array-callback entry for NON-killing hits. Killing hits are skipped by vanilla
// enemy_death_detection (its !isalive gate) and are instead fired on the spot by
// zh_killed_hook. Signature from
// check_zombie_damage_callbacks: ( mod, hit_location, hit_origin, player, amount ),
// self = the damaged zombie. Return false so we never suppress the damage path.
zh_actor_damage_hook( mod, hit_location, hit_origin, player, amount )
{
	if( !isDefined( player ) || !IsPlayer( player ) || !isDefined( amount ) )
		return false;

	// Only numbers the player actually caused (never self/other AI).
	if( player == self )
		return false;

	// Cache the real hit coordinate; a later killing blow (zh_killed_hook) reuses it.
	if( isDefined( hit_origin ) )
		self.zh_lastHitOrigin = hit_origin;

	// Non-killing hits ONLY: a live zombie reaches here via the array callback,
	// while the killing blow is fired by zh_killed_hook instead.
	self zh_fire_number( player, amount, hit_origin );
	return false;
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
		crawlers = zh_crawlers();
		// ONE flat pool: zombie_team + dogs + crawlers, de-duplicated, because a
		// crawler may ALSO be registered in zombie_team - two entries for the same
		// entity would push two bars onto one anchor.
		pool = [];
		for ( p = 0; p < zombies.size; p++ )
			pool[ pool.size ] = zombies[p];
		for ( p = 0; p < dogs.size; p++ )
		{
			dup = false;
			for ( q = 0; q < pool.size; q++ )
				if ( pool[q] == dogs[p] )
					dup = true;
			if ( !dup )
				pool[ pool.size ] = dogs[p];
		}
		for ( p = 0; p < crawlers.size; p++ )
		{
			dup = false;
			for ( q = 0; q < pool.size; q++ )
				if ( pool[q] == crawlers[p] )
					dup = true;
			if ( !dup )
				pool[ pool.size ] = crawlers[p];
		}
		for ( p = 0; p < pool.size; p++ )
		{
			z = pool[p];

			if ( !isDefined( z ) )
				continue;
			// Hellhounds are NOT in level.zombie_team, so they come in via the
			// "zombie_dog" targetname; crawlers may live in either place. The de-dupe
			// above guarantees exactly one payload entry per entity.

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
			if ( d <= 300 )                                        // beyond this: hidden
			{
				if ( bullettracepassed( eyePos, ( z.origin + ( 0, 0, 40 ) ), 0, self ) )
				{
					if ( d <= 150 )                                // within this: full 0.85
						alpha = 0.85;
					else
						alpha = 0.85 * ( 300 - d ) / ( 300 - 150 );   // linear fade 150 -> 300
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
			// NO distance cap: whatever the crosshair is on (and has line of sight to)
			// reveals its bar, however far away it is.
			if ( aimed )
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

			// ONE dispatcher decides the label. animname is THE discriminator BO2 uses
			// for every special zombie (each AI script assigns it): plain zombies
			// "zombie" (_zm_spawner.gsc:179), dogs "zombie_dog" (_zm_ai_dogs.gsc:398),
			// the theater crawler "quad_zombie" (zzz_zm_quaddescent.gsc:205), the
			// Origins mech "mechz_zombie" (_zm_ai_mechz.gsc:527), etc. Their
			// targetname/classname are all "zombie"/"actor", so this is the only
			// reliable field. Adding a new kind = one else-if here + one colour row in
			// the LUI's ICON_TINT table.
			an = "";
			if ( isDefined( z.animname ) )
				an = z.animname;
			zname = "ZOMBIE";
			if ( an == "zombie_dog" || ( isDefined( z.isdog ) && z.isdog ) )
				zname = "HELLHOUND";
			else if ( an == "quad_zombie" || ( isDefined( z.zh_isCrawler ) && z.zh_isCrawler ) )
				zname = "CRAWLER";
			else if ( an == "mechz_zombie" )
				zname = "MECH";
			else if ( an == "screecher_zombie" )
				zname = "SHRIEKER";
			else if ( an == "leaper_zombie" )
				zname = "LEAPER";
			else if ( an == "ghost_zombie" )
				zname = "GHOST";
			else if ( an == "brutus_zombie" || ( isDefined( z.is_brutus ) && z.is_brutus ) )
				zname = "WARDEN";   // MoD jailer label; is_brutus is the stock flag (_zm_ai_brutus.gsc:282)
			else if ( an == "astro_zombie" )
				zname = "ASTRO";
			else if ( an == "monkey_zombie" )
				zname = "MONKEY";
			else if ( an == "giant_robot_walker" )
				zname = "ROBOT";
			else if ( an == "napalm_zombie" )
				zname = "FLAME";   // temple's fire zombie; name came from the live probe
			// OPT-IN SELF-REPORTING PROBE (default OFF): with `setdvar zh_animname 1`
			// any zombie whose animname is NOT mapped above prints its raw animname as
			// the label, so an unknown monster kind reveals its own real name on screen;
			// read it off the bar, add a row here + a colour row in ICON_TINT, then turn
			// the probe back off. Because this is the LAST else-if, the getdvar only runs
			// for already-unmapped entities - zero cost for the normal crowd, and 0 (or
			// an unset dvar) keeps the plain ZOMBIE label.
			else if ( an != "" && an != "zombie" && getdvar( "zh_animname" ) == "1" )
				zname = an;

			// entNum:ratio:alpha:name (no ':' or ';' in any field)
			if ( cur != "" )
				cur = cur + ";";
			// Follow the bone anchor when we have one -> the bar sits at the eyes
			// instead of "feet origin + fixed pixel offset". The payload keeps the
			// same field count, so the LUI parser is unchanged.
			barEnt = entNum;
			if ( isDefined( z.zh_headAnchor ) && isDefined( z.zh_headAnchor.zh_entNum ) )
				barEnt = z.zh_headAnchor.zh_entNum;
			cur = cur + barEnt + ":" + int( ratio * 100 + 0.5 ) + ":" + int( alpha * 100 + 0.5 ) + ":" + zname + ":" + int( d );
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

		// ---- kill notices ----
		// Same shape as the damage queue but events live longer: the LUI keeps a
		// notice up for ~1s, so the queue has to survive long enough for the 0.1s
		// poller to catch it, even during a fast double kill. Format: "seq:score:crit".
		if( !isDefined( self.zh_killList ) )
		{
			self.zh_killList = [];
			self.zh_killTimes = [];
		}
		newKill = [];
		newKillTimes = [];
		killStr = "";
		kf = 1;
		for( i = 0; i < self.zh_killList.size; i++ )
		{
			if( now - self.zh_killTimes[i] <= 1200 )
			{
				if( kf )
					kf = 0;
				else
					killStr = killStr + ";";
				killStr = killStr + self.zh_killList[i];
				newKill[ newKill.size ] = self.zh_killList[i];
				newKillTimes[ newKillTimes.size ] = self.zh_killTimes[i];
			}
		}
		self.zh_killList = newKill;
		self.zh_killTimes = newKillTimes;
		self setclientdvar( "zh_kill", killStr );
		wait 0.05;
	}
}
