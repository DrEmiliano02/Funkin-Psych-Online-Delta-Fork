package backend.system;

import backend.Paths;
import openfl.system.System;

class BitmapDiagnostics
{
    // Turn off after a profiling session if you do not want report I/O.
    public static var enabled:Bool = true;
    public static var songLabel:String = "(no song)";
    public static var imageLoads:Int = 0;
    public static var imageCacheHits:Int = 0;
    public static var graphicsCreated:Int = 0;
    public static var peakRuntimeBytes:Float = 0;
    public static var longestLoadMs:Float = 0;

    static var slowestLoads:Array<{key:String, milliseconds:Float, estimatedMiB:Float}> = [];
    static inline var MAX_SLOW_LOADS:Int = 15;

    public static function beginSong(name:String):Void
    {
        songLabel = name == null ? "(unknown)" : name;
        imageLoads = 0;
        imageCacheHits = 0;
        graphicsCreated = 0;
        peakRuntimeBytes = 0;
        longestLoadMs = 0;
        slowestLoads = [];
    }

    public static function noteMemory():Void
    {
        if (!enabled) return;
        #if cpp
        var value:Float = System.totalMemory;
        if (value > peakRuntimeBytes) peakRuntimeBytes = value;
        #end
    }

    public static function recordImageLoad(key:String, width:Int, height:Int, milliseconds:Float):Void
    {
        if (!enabled) return;
        imageLoads++;
        noteMemory();
        if (milliseconds > longestLoadMs) longestLoadMs = milliseconds;
        slowestLoads.push({key: key, milliseconds: milliseconds,
            estimatedMiB: 4.0 * width * height / (1024.0 * 1024.0)});
        slowestLoads.sort(function(a, b):Int {
            return a.milliseconds > b.milliseconds ? -1 : (a.milliseconds < b.milliseconds ? 1 : 0);
        });
        if (slowestLoads.length > MAX_SLOW_LOADS) slowestLoads.pop();
    }

    public static function recordCacheHit():Void
    {
        if (!enabled) return;
        imageCacheHits++;
    }

    public static function recordGraphicCreated():Void
    {
        if (!enabled) return;
        graphicsCreated++;
        noteMemory();
    }

    static function rounded(value:Float):Float
    {
        return Math.round(value * 10) / 10.0;
    }

    /** Writes one readable report on state boundaries; never per frame. */
    public static function snapshot(phase:String):Void
    {
        if (!enabled) return;
        #if (cpp && !mobile)
        noteMemory();
        var entries:Array<{key:String, mib:Float, width:Int, height:Int}> = [];
        var totalEstimatedMiB:Float = 0;
        for (key in Paths.currentTrackedAssets.keys())
        {
            var graphic = Paths.currentTrackedAssets.get(key);
            if (graphic == null || graphic.bitmap == null) continue;
            var bitmap = graphic.bitmap;
            var mib:Float = 4.0 * bitmap.width * bitmap.height / (1024.0 * 1024.0);
            entries.push({key: key, mib: mib, width: bitmap.width, height: bitmap.height});
            totalEstimatedMiB += mib;
        }
        entries.sort(function(a, b):Int {
            return a.mib > b.mib ? -1 : (a.mib < b.mib ? 1 : 0);
        });

        var out = new StringBuf();
        out.add("\n=== Bitmap v3.2.3 | " + Date.now().toString() + " | " + songLabel
            + " | " + phase + " ===\n");
        out.add("Runtime reported RAM: " + rounded(System.totalMemory / (1024.0 * 1024.0)) + " MiB");
        out.add(" | peak sampled: " + rounded(peakRuntimeBytes / (1024.0 * 1024.0)) + " MiB\n");
        out.add("Tracked FlxGraphics: " + entries.length + " | sum of dimensions x4: "
            + rounded(totalEstimatedMiB) + " MiB (estimate, NOT measured allocation)\n");
        out.add("Images requested via Paths.image: " + imageLoads + " | cached reuses: "
            + imageCacheHits + " | graphics created (incl. async): " + graphicsCreated + "\n");
        out.add("GPU: " + OptimizedBitmapData.diagnostics() + "\n");
        out.add("Top " + Std.int(Math.min(15, entries.length)) + " tracked image dimensions:\n");
        for (i in 0...Std.int(Math.min(15, entries.length)))
        {
            var e = entries[i];
            out.add("  " + rounded(e.mib) + " MiB | " + e.width + "x" + e.height + " | " + e.key + "\n");
        }
        out.add("Top " + slowestLoads.length + " Paths.image retrieval/decode times (includes file/cache lookup):\n");
        for (e in slowestLoads)
            out.add("  " + rounded(e.milliseconds) + " ms | ~" + rounded(e.estimatedMiB)
                + " MiB | " + e.key + "\n");
        out.add("=== end ===\n");

        var report:String = out.toString();
        trace(report);
        try
        {
            var file = sys.io.File.append("bitmap_diagnostics.txt", false);
            file.writeString(report);
            file.close();
        }
        catch (e:Dynamic)
        {
            // A read-only installation must not prevent the game from running.
            trace("BitmapDiagnostics: could not write report: " + Std.string(e));
        }
        #end
    }
}
