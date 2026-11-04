package backend.system;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;

class OptimizedBitmapData
{
    public static var enabled(default, null):Bool = false;

    // Optional prewarming budget: a single 4096x4096 RGBA atlas is ~64 MiB.
    // Lower this to 16 * 1024 * 1024 if large uploads cause frame hitches.
    // This is a size *limit*, not a CPU-memory or VRAM allocation limit.
    public static var MAX_PREWARM_BYTES:Float = 64.0 * 1024 * 1024;
    public static inline var MAX_PENDING:Int = 512;
    public static inline var MIN_INTERVAL_SECONDS:Float = 0.025;

    // Diagnostics: these are API call counts, NOT proof of newly allocated
    // VRAM, and should not be interpreted as GPU-memory measurements.
    public static var cacheHits:Int = 0;
    public static var queuedTextures:Int = 0;
    public static var preparedTextures:Int = 0;
    public static var failedTextures:Int = 0;
    public static var skippedLargeTextures:Int = 0;
    public static var skippedOverflowTextures:Int = 0;
    public static var discardedStaleTextures:Int = 0;
    public static var requestedEstimatedMiB:Float = 0;
    public static var pendingCount(get, never):Int;

    static var pending:Array<FlxGraphic> = [];
    static var listening:Bool = false;
    static var lastUploadTime:Float = 0;
    static var lastContext:Dynamic = null;

    static function get_pendingCount():Int
    {
        return pending.length;
    }

    public static function configure(value:Bool):Void
    {
        #if (cpp && !mobile)
        var wasEnabled:Bool = enabled;
        enabled = value;
        if (!enabled)
        {
            pending = [];
            return;
        }

        installListener();
        if (!wasEnabled)
        {
            lastUploadTime = 0;
            // When toggled in the menu, graphics may already be in RAM.
            // Prepare those already tracked by Paths as well as future loads.
            for (graphic in backend.Paths.currentTrackedAssets)
                prepare(graphic);
        }
        #else
        enabled = false;
        pending = [];
        #end
    }

    static function installListener():Void
    {
        #if (cpp && !mobile)
        if (!listening)
        {
            FlxG.signals.postUpdate.add(processQueue);
            listening = true;
        }
        // Intentionally do not clear the queue on preStateSwitch.
        // Stale entries are discarded before touching their BitmapData.
        #end
    }

    public static function prepare(graphic:FlxGraphic, ?allowGPU:Bool = true):Void
    {
        #if (cpp && !mobile)
        if (!enabled || !allowGPU || graphic == null || graphic.bitmap == null)
            return;

        var bitmap = graphic.bitmap;
        if (bitmap.width <= 0 || bitmap.height <= 0)
            return;

        var estimatedBytes:Float = 4.0 * bitmap.width * bitmap.height;
        if (estimatedBytes > MAX_PREWARM_BYTES)
        {
            skippedLargeTextures++;
            return;
        }

        if (pending.indexOf(graphic) != -1)
            return;

        if (pending.length >= MAX_PENDING)
        {
            skippedOverflowTextures++;
            return;
        }

        installListener();
        pending.push(graphic);
        queuedTextures++;
        #end
    }

    static function processQueue():Void
    {
        #if (cpp && !mobile)
        if (!enabled || pending.length == 0 || FlxG.stage == null)
            return;

        var context = FlxG.stage.context3D;
        if (context == null)
            return;

        // A new context requires textures to be prepared again. We retain
        // CPU pixel data so OpenFL can restore them if necessary.
        if (context != lastContext)
        {
            lastContext = context;
            lastUploadTime = 0;
        }

        var now:Float = haxe.Timer.stamp();
        if (now - lastUploadTime < MIN_INTERVAL_SECONDS)
            return;
        lastUploadTime = now;

        var graphic:FlxGraphic = pending.shift();
        if (graphic == null || graphic.bitmap == null)
        {
            discardedStaleTextures++;
            return;
        }

        // Paths' tracked cache is the owner of these prewarm requests.
        // After state changes, never upload a replaced/evicted graphic.
        if (graphic.key == null || backend.Paths.currentTrackedAssets.get(graphic.key) != graphic)
        {
            discardedStaleTextures++;
            return;
        }

        try
        {
            var texture = graphic.bitmap.getTexture(context);
            if (texture != null)
            {
                preparedTextures++;
                requestedEstimatedMiB += (4.0 * graphic.bitmap.width * graphic.bitmap.height) / (1024 * 1024);
            }
            else
                failedTextures++;
        }
        catch (e:Dynamic)
        {
            failedTextures++;
            #if debug
            trace('GPU texture prewarm failed (CPU pixels preserved): ' + Std.string(e));
            #end
        }
        #end
    }

    public static function diagnostics():String
    {
        return 'GPU Caching=' + enabled
            + ' | pending=' + pending.length
            + ' | enqueued=' + queuedTextures
            + ' | successful getTexture=' + preparedTextures
            + ' | failures=' + failedTextures
            + ' | tooLarge=' + skippedLargeTextures
            + ' | queueFull=' + skippedOverflowTextures
            + ' | stale=' + discardedStaleTextures;
    }
}
