package backend.system;

import flixel.FlxG;
import openfl.display.BitmapData;

class OptimizedBitmapData
{
    public static var enabled:Bool = false;

    public static function prepare(bitmap:BitmapData, ?allowGPU:Bool = true):Void
    {
        #if (cpp && !mobile)
        if (!enabled || !allowGPU || bitmap == null) return;
        if (FlxG.stage == null || FlxG.stage.context3D == null) return;

        try
        {
            // OpenFL internally reuses an existing texture for this Context3D.
            bitmap.getTexture(FlxG.stage.context3D);
        }
        catch (e:Dynamic)
        {
            #if debug
            trace('GPU prewarm failed (kept CPU image): ' + Std.string(e));
            #end
        }
        #end
    }
}
