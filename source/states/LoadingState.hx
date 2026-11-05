package states;

import lime.app.Promise;
import lime.app.Future;

import flixel.FlxState;

import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;
import lime.utils.AssetLibrary;
import lime.utils.AssetManifest;

import backend.StageData;

import haxe.io.Path;

class LoadingState extends MusicBeatState
{
	inline static var MIN_TIME = 1.0;

	// Browsers will load create(), you can make your song load a custom directory there
	// If you're compiling to desktop (or something that doesn't use NO_PRELOAD_ALL), search for getNextState instead
	// I'd recommend doing it on both actually lol
	
	// TO DO: Make this easier
	
	var target:FlxState;
	var stopMusic = false;
	var directory:String;
	var callbacks:MultiCallback;
	var targetShit:Float = 0;
	// A failed/abandoned loading screen must not switch to an incomplete PlayState.
	var loadFailed:Bool = false;
	var loadFinished:Bool = false;
	var loadReady:Bool = false;
	var loadFailureReason:String;
	var stateDisposed:Bool = false;
	var introTimer:FlxTimer;
	var errorText:FlxText;

	function new(target:FlxState, stopMusic:Bool, directory:String)
	{
		super();
		this.target = target;
		this.stopMusic = stopMusic;
		this.directory = directory;
	}

	var funkay:FlxSprite;
	var loadBar:FlxSprite;
	override function create()
	{
		var bg:FlxSprite = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xffcaff4d);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		funkay = new FlxSprite(0, 0).loadGraphic(Paths.getPath('images/funkay.png', IMAGE));
		funkay.setGraphicSize(0, FlxG.height);
		funkay.updateHitbox();
		add(funkay);
		funkay.antialiasing = ClientPrefs.data.antialiasing;
		funkay.scrollFactor.set();
		funkay.screenCenter();

		loadBar = new FlxSprite(0, FlxG.height - 20).makeGraphic(FlxG.width, 10, 0xffff16d2);
		loadBar.screenCenter(X);
		add(loadBar);
		
		initSongsManifest().onComplete(function(lib)
		{
			if (stateDisposed || loadFailed || loadFinished) return;
			callbacks = new MultiCallback(onLoad);
			var introComplete = callbacks.add("introComplete");
			if (PlayState.SONG != null) {
				checkLoadSong(getSongPath());
				if (PlayState.SONG.needsVoices)
					checkLoadSong(getVocalPath());
			}
			checkLibrary("shared");
			if (directory != null && directory.length > 0 && directory != 'shared')
				checkLibrary('week_assets');

			if (loadFailed) return;
			var fadeTime = 0.5;
			FlxG.camera.fade(FlxG.camera.bgColor, fadeTime, true);
			introTimer = new FlxTimer().start(fadeTime + MIN_TIME, function(_) {
				if (!stateDisposed && !loadFailed && !loadFinished) introComplete();
			});
		}).onError(function(error:Dynamic) {
			failLoad('Could not load songs manifest: ' + Std.string(error));
		});
	}
	
	function failLoad(message:String):Void
	{
		if (stateDisposed || loadFinished || loadFailed) return;
		// Future callbacks may not run on the game thread. The UI is created in update().
		loadFailureReason = message;
		loadFailed = true;
		Log.error(message);
	}

	function checkLoadSong(path:String):Void
	{
		if (loadFailed || stateDisposed || path == null || path.length == 0) return;
		if (!Assets.cache.hasSound(path))
		{
			var done = callbacks.add('song:' + path);
			try {
				Assets.loadSound(path).onComplete(function(_) {
					if (!stateDisposed && !loadFailed) done();
				}).onError(function(error:Dynamic) {
					failLoad('Sound ' + path + ': ' + Std.string(error));
				});
			} catch (error:Dynamic) {
				failLoad('Sound ' + path + ': ' + Std.string(error));
			}
		}
	}

	function checkLibrary(library:String):Void
	{
		if (loadFailed || stateDisposed || Assets.getLibrary(library) != null) return;
		@:privateAccess
		if (!LimeAssets.libraryPaths.exists(library)) {
			failLoad('Missing library: ' + library);
			return;
		}

		var done = callbacks.add('library:' + library);
		try {
			Assets.loadLibrary(library).onComplete(function(_) {
				if (!stateDisposed && !loadFailed) done();
			}).onError(function(error:Dynamic) {
				failLoad('Library ' + library + ': ' + Std.string(error));
			});
		} catch (error:Dynamic) {
			failLoad('Library ' + library + ': ' + Std.string(error));
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (stateDisposed || loadFinished) return;
		if (loadFailed) {
			if (introTimer != null) { introTimer.cancel(); introTimer = null; }
			if (errorText == null) {
				errorText = new FlxText(20, FlxG.height - 145, FlxG.width - 40,
					'Loading error: ' + loadFailureReason + '\nPress BACK to return to Freeplay.', 18);
				errorText.color = FlxColor.WHITE;
				errorText.scrollFactor.set();
				add(errorText);
			}
			if (controls.BACK) {
				loadFinished = true;
				FlxG.switchState(() -> new FreeplayState());
			}
			return;
		}
		if (loadReady) {
			loadReady = false;
			loadFinished = true;
			if (introTimer != null) introTimer.cancel();
			if (stopMusic && FlxG.sound.music != null) FlxG.sound.music.stop();
			FlxG.switchState(() -> target);
			return;
		}
		funkay.setGraphicSize(Std.int(0.88 * FlxG.width + 0.9 * (funkay.width - 0.88 * FlxG.width)));
		funkay.updateHitbox();
		if(controls.ACCEPT)
		{
			funkay.setGraphicSize(Std.int(funkay.width + 60));
			funkay.updateHitbox();
		}

		if(callbacks != null) {
			targetShit = FlxMath.remapToRange(callbacks.numRemaining / callbacks.length, 1, 0, 0, 1);
			loadBar.scale.x += 0.5 * (targetShit - loadBar.scale.x);
		}
	}
	
	function onLoad()
	{
		if (stateDisposed || loadFailed || loadFinished) return;
		// The actual state transition happens in update(), on the main thread.
		loadReady = true;
	}
	
	static function getSongPath()
	{
		return Paths.inst(PlayState.SONG.song);
	}
	
	static function getVocalPath()
	{
		return Paths.voices(PlayState.SONG.song);
	}
	
	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false)
	{
		FlxG.switchState(() -> getNextState(target, stopMusic));
	}
	
	static function getNextState(target:FlxState, stopMusic = false):FlxState
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		if(weekDir != null && weekDir.length > 0 && weekDir != '') directory = weekDir;

		Paths.setCurrentLevel(directory);
		Log.info('Setting asset folder to ' + directory);

		#if NO_PRELOAD_ALL
		var loaded:Bool = false;
		if (PlayState.SONG != null) {
			loaded = isSoundLoaded(getSongPath()) && (!PlayState.SONG.needsVoices || isSoundLoaded(getVocalPath())) && isLibraryLoaded("shared")
				&& (directory == 'shared' || isLibraryLoaded('week_assets'));
		}
		
		if (!loaded)
			return new LoadingState(target, stopMusic, directory);
		#end
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();
		
		return target;
	}
	
	#if NO_PRELOAD_ALL
	static function isSoundLoaded(path:String):Bool
	{
		Log.infoTrace(path);
		return Assets.cache.hasSound(path);
	}
	
	static function isLibraryLoaded(library:String):Bool
	{
		return Assets.getLibrary(library) != null;
	}
	#end
	
	override function destroy()
	{
		stateDisposed = true;
		if (introTimer != null) {
			introTimer.cancel();
			introTimer = null;
		}
		callbacks = null;
		super.destroy();
	}
	
	static function initSongsManifest()
	{
		var id = "songs";
		var promise = new Promise<AssetLibrary>();

		var library = LimeAssets.getLibrary(id);

		if (library != null)
		{
			return Future.withValue(library);
		}

		var path = id;
		var rootPath = null;

		@:privateAccess
		var libraryPaths = LimeAssets.libraryPaths;
		if (libraryPaths.exists(id))
		{
			path = libraryPaths[id];
			rootPath = Path.directory(path);
		}
		else
		{
			if (StringTools.endsWith(path, ".bundle"))
			{
				rootPath = path;
				path += "/library.json";
			}
			else
			{
				rootPath = Path.directory(path);
			}
			@:privateAccess
			path = LimeAssets.__cacheBreak(path);
		}

		AssetManifest.loadFromFile(path, rootPath).onComplete(function(manifest)
		{
			if (manifest == null)
			{
				promise.error("Cannot parse asset manifest for library \"" + id + "\"");
				return;
			}

			var library = AssetLibrary.fromManifest(manifest);

			if (library == null)
			{
				promise.error("Cannot open library \"" + id + "\"");
			}
			else
			{
				@:privateAccess
				LimeAssets.libraries.set(id, library);
				library.onChange.add(LimeAssets.onChange.dispatch);
				promise.completeWith(Future.withValue(library));
			}
		}).onError(function(_)
		{
			promise.error("There is no asset library with an ID of \"" + id + "\"");
		});

		return promise.future;
	}
}

class MultiCallback
{
	public var callback:Void->Void;
	public var logId:String = null;
	public var length(default, null) = 0;
	public var numRemaining(default, null) = 0;
	
	var unfired = new Map<String, Void->Void>();
	var fired = new Array<String>();
	
	public function new (callback:Void->Void, logId:String = null)
	{
		this.callback = callback;
		this.logId = logId;
	}
	
	public function add(id = "untitled")
	{
		id = '$length:$id';
		length++;
		numRemaining++;
		var func:Void->Void = null;
		func = function ()
		{
			if (unfired.exists(id))
			{
				unfired.remove(id);
				fired.push(id);
				numRemaining--;
				
				if (logId != null)
					log('fired $id, $numRemaining remaining');
				
				if (numRemaining == 0)
				{
					if (logId != null)
						log('all callbacks fired');
					callback();
				}
			}
			else
				log('already fired $id');
		}
		unfired[id] = func;
		return func;
	}
	
	inline function log(msg):Void
	{
		if (logId != null)
			Log.trace('$logId: $msg');
	}
	
	public function getFired() return fired.copy();
	public function getUnfired() return [for (id in unfired.keys()) id];
}