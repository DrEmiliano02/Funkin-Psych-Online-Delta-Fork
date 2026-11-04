package backend.system;

import backend.Paths;
import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import objects.Character;
import states.PlayState;
import openfl.utils.Assets as OpenFlAssets;

@:access(backend.Paths)
class BitmapMemoryManager
{
    public static var evicted:Int = 0;
    public static var busy:Int = 0;
    public static var missing:Int = 0;
    public static var deferred:Int = 0;
    public static var estimatedRemovedMiB:Float = 0;

    static function normalizePath(path:String):String
    {
        if (path == null) return null;
        var result = StringTools.trim(path).split('\\').join('/');
        if (StringTools.startsWith(result, 'images/')) result = result.substr(7);
        if (StringTools.endsWith(result, '.png')) result = result.substr(0, result.length - 4);
        return result.length > 0 ? result : null;
    }

    /** Removes all atlas lookup entries whose parent is exactly this graphic. */
    static function forgetAtlasCollections(graphic:FlxGraphic):Void
    {
        var sparrowKeys:Array<String> = [];
        for (key in Paths.sparrowAtlasCache.keys())
        {
            var frames = Paths.sparrowAtlasCache.get(key);
            if (frames != null && frames.parent == graphic)
                sparrowKeys.push(key);
        }
        for (key in sparrowKeys) Paths.sparrowAtlasCache.remove(key);

        var packerKeys:Array<String> = [];
        for (key in Paths.packerAtlasCache.keys())
        {
            var frames = Paths.packerAtlasCache.get(key);
            if (frames != null && frames.parent == graphic)
                packerKeys.push(key);
        }
        for (key in packerKeys) Paths.packerAtlasCache.remove(key);
    }

    public static function removeImage(imagePath:String, ?immediate:Bool = true):Bool
    {
        var logical = normalizePath(imagePath);
        if (logical == null) return false;

        // Paths.imageCacheKey uses the same mod-folder resolution as Paths.image.
        var key:String = Paths.imageCacheKey(logical);
        if (key == null || key.length == 0) return false;

        var graphic:FlxGraphic = Paths.currentTrackedAssets.get(key);
        if (graphic == null) graphic = FlxG.bitmap.get(key);
        if (graphic == null || graphic.bitmap == null)
        {
            missing++;
            return false;
        }

        // Never evict a texture while a FlxSprite is still referencing it.
        if (graphic.useCount > 0)
        {
            busy++;
            return false;
        }

        if (!immediate)
        {
            graphic.persist = false;
            graphic.destroyOnNoUse = true;
            deferred++;
            return false;
        }

        var estimatedMiB:Float = (4.0 * graphic.bitmap.width * graphic.bitmap.height) / (1024.0 * 1024.0);

        // Prevent a queued getTexture() on this image after eviction.
        OptimizedBitmapData.forgetGraphic(graphic);
        // FlxAtlasFrames cached by Paths may otherwise retain a stale parent.
        forgetAtlasCollections(graphic);

        Paths.currentTrackedAssets.remove(key);
        while (Paths.localTrackedAssets.remove(key)) {}

        graphic.persist = false;
        graphic.destroyOnNoUse = true;

        if (FlxG.bitmap.get(key) == graphic)
        {
            // removeByKey() ALREADY destroys the FlxGraphic.
            FlxG.bitmap.removeByKey(key);
        }
        else
        {
            OpenFlAssets.cache.removeBitmapData(key);
            graphic.destroy();
        }

        evicted++;
        estimatedRemovedMiB += estimatedMiB;
        return true;
    }

    public static function removeCharacter(characterName:String, ?immediate:Bool = true):Bool
    {
        var game = PlayState.instance;
        if (game == null || characterName == null || characterName.length == 0) return false;

        var char:Character = null;
        if (game.boyfriendMap.exists(characterName)) char = game.boyfriendMap.get(characterName);
        if (char == null && game.dadMap.exists(characterName)) char = game.dadMap.get(characterName);
        if (char == null && game.gfMap.exists(characterName)) char = game.gfMap.get(characterName);
        if (char == null) return false;

        if (char == game.boyfriend || char == game.dad || char == game.gf) return false;
        for (other in game.characters) if (other == char) return false;

        var images:String = char.imageFile;
        game.boyfriendGroup.remove(char, true);
        game.dadGroup.remove(char, true);
        game.gfGroup.remove(char, true);
        game.boyfriendMap.remove(characterName);
        game.dadMap.remove(characterName);
        game.gfMap.remove(characterName);
        char.kill();
        char.destroy();

        if (images != null && images.length > 0)
        {
            // Multi-atlas characters store image paths separated by commas.
            for (image in images.split(',')) removeImage(image, immediate);
        }
        return true;
    }

    public static function diagnostics():String
    {
        return 'BitmapMemoryManager | evicted=' + evicted + ' | busy=' + busy
            + ' | missing=' + missing + ' | deferred=' + deferred
            + ' | removedRGBAEstimate=' + Math.round(estimatedRemovedMiB * 10) / 10.0 + ' MiB';
    }
}
