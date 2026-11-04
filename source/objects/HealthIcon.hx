package objects;

import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets.FlxGraphicAsset;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isOldIcon:Bool = false;
	public var isPlayer:Bool = false;
	private var char:String = '';
	public var ox:Int;

	public function new(char:String = 'bf', isPlayer:Bool = false, ?allowGPU:Bool = false)
	{
		super();
		isOldIcon = (char == 'bf-old');
		this.isPlayer = isPlayer;
		if (char != null)
			changeIcon(char, allowGPU);
		scrollFactor.set();
	}

	override function update(elapsed:Float) {
		snapToTracker();

		super.update(elapsed);
	}

	public function snapToTracker() {
		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y - 30);
	}

	public static function findIconPath(char:String) {
		var name:String = 'icons/' + char;
		if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
		if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon
		return name;
	}

	private var iconOffsets:Array<Float> = [0, 0];
	public function changeIcon(char:String, ?allowGPU:Bool = false) {
		if(this.char != char) {
			var name:String = findIconPath(char);
			
			var graphic = Paths.image(name, null, allowGPU);
			if (graphic == null) {
				if (char != 'face')
					changeIcon('face');
				return;
			}

			this.char = char;
			loadIcon(graphic);
		}
	}

	public function loadIcon(asset:FlxGraphicAsset, ?iconCharacter:String):Void
	{
		if (iconCharacter != null)
		{
			char = iconCharacter;
			isOldIcon = (char == 'bf-old');
		}
		if (asset == null || char == null || char.length == 0)
			return;

		var graphic:FlxGraphic = Std.isOfType(asset, FlxGraphic) ? cast asset : null;
		var frameCount:Int = 1;
		if (graphic != null && graphic.bitmap != null && graphic.bitmap.height > 0)
		{
			var w:Int = graphic.bitmap.width;
			var h:Int = graphic.bitmap.height;
			frameCount = Std.int(Math.max(1, Math.round(w / h)));
			// Tell HaxeFlixel the frame dimensions instead of mutating a
			// potentially shared tileSize after the frames were created.
			loadGraphic(asset, true, Std.int(w / frameCount), h);
		}
		else
		{
			loadGraphic(asset, true);
		}

		if (frames == null || frames.frames == null || frames.frames.length == 0)
			return;

		if (graphic == null)
			frameCount = frames.frames.length;
		iconOffsets[0] = (width - 150) / frameCount;
		iconOffsets[1] = (height - 150) / frameCount;
		updateHitbox();

		animation.add(char, [for (i in 0...frames.frames.length) i], 0, false, isPlayer);
		animation.play(char);

		antialiasing = !char.endsWith('-pixel') && ClientPrefs.data.antialiasing;
	}

	override function updateHitbox()
	{
		super.updateHitbox();
		offset.x = iconOffsets[0];
		offset.y = iconOffsets[1];
	}

	public function getCharacter():String {
		return char;
	}
}
