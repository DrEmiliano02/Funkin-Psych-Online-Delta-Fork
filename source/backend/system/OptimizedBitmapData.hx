package backend.system;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;

class OptimizedBitmapData
{
    public static var enabled(default, null):Bool = false;

    // A single large upload could stall a frame; do not eagerly upload
    // atlases above this *estimated uncompressed* byte size (16 MiB).
    public static inline var MAX_PREWARM_BYTES:Float = 16 * 1024 * 1024;
    public static inline var MAX_PENDING:Int = 24;

    public static var cacheHits:Int = 0;
    public static var preparedTextures:Int = 0;
    public static var skippedLargeTextures:Int = 0;

    static var pending:Array<FlxGraphic> = [];
    static var listening:Bool = false;
    static var lastUploadTime:Float = 0;

    public static function configure(value:Bool):Void
    {
        #if (cpp && !mobile)
        enabled = value;
        if (!enabled) pending = [];
        #else
        enabled = false;
        pending = [];
        #end
    }

    public static function prepare(graphic:FlxGraphic, ?allowGPU:Bool = true):Void
    {
        #if (cpp && !mobile)
        if (!enabled || !allowGPU || graphic == null || graphic.bitmap == null) return;
        if (FlxG.stage == null) return;

        var bitmap = graphic.bitmap;
        if (bitmap.width <= 0 || bitmap.height <= 0) return;
        var estimatedBytes:Float = 4.0 * bitmap.width * bitmap.height;
        if (estimatedBytes > MAX_PREWARM_BYTES)
        {
            skippedLargeTextures++;
            return;
        }

        if (pending.length >= MAX_PENDING || pending.indexOf(graphic) != -1) return;
        if (!listening)
        {
            FlxG.signals.postUpdate.add(processQueue);
            FlxG.signals.preStateSwitch.add(clearQueue);
            listening = true;
        }
        pending.push(graphic);
        #end
    }

    static function clearQueue():Void
    {
        pending = [];
    }

    static function processQueue():Void
    {
        #if (cpp && !mobile)
        if (!enabled || pending.length == 0) return;
        if (FlxG.stage == null || FlxG.stage.context3D == null) return;

        // Not more than about one GPU prewarm every 16 ms, even at 120+ updates/s.
        var now:Float = haxe.Timer.stamp();
        if (now - lastUploadTime < 0.016) return;
        lastUploadTime = now;

        var graphic:FlxGraphic = pending.shift();
        if (graphic == null || graphic.bitmap == null) return;

        // If a state transition destroyed/replaced it, do not touch a stale texture.
        if (graphic.key == null || backend.Paths.currentTrackedAssets.get(graphic.key) != graphic)
            return;

        try
        {
            graphic.bitmap.getTexture(FlxG.stage.context3D);
            preparedTextures++;
        }
        catch (e:Dynamic)
        {
            #if debug
            trace('GPU prewarm skipped (CPU bitmap preserved): ' + Std.string(e));
            #end
        }
        #end
    }
}
