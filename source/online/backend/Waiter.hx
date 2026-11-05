package online.backend;

import flixel.FlxBasic;
import sys.thread.Mutex;

//thread safe function handler
class Waiter extends FlxBasic {
    // separated into two queues because sometimes a task is targeted to be run for a specific flxstate
    // this clears after the flxstate switches
	public static var stateQueue:Array<Dynamic> = [];
	private static var persistQueue(default, never):Array<Dynamic> = [];
	// Temporized tasks are kept separate so an online retry never sleeps on the game thread.
	private static var delayedPersistQueue:Array<Dynamic> = [];
	private static inline var MAX_TASKS_PER_UPDATE:Int = 64;
	private static var stateQueueGeneration:Int = 0;

    var _queueRAW:Dynamic;
    var _queueCall:Void->Void;
    var _queueCallPos:haxe.PosInfos;

	static var queueMutex:Mutex = new Mutex();

	public static function put(func:Void->Void, ?pos:haxe.PosInfos) {
		queueMutex.acquire();
		stateQueue.push([func, pos]);
		queueMutex.release();
    }

	public static function putPersist(func:Void->Void, ?pos:haxe.PosInfos) {
		queueMutex.acquire();
		persistQueue.push([func, pos]);
		queueMutex.release();
    }

	public static function clearStateQueue() {
		queueMutex.acquire();
		stateQueueGeneration++;
		stateQueue = [];
		queueMutex.release();
	}

	/** Schedule work on the main thread, without blocking it with Sys.sleep(). */
	public static function putDelayedPersist(func:Void->Void, delaySeconds:Float, ?pos:haxe.PosInfos):Void {
		if (func == null) return;
		var due:Float = haxe.Timer.stamp() + Math.max(0, delaySeconds);
		queueMutex.acquire();
		delayedPersistQueue.push([func, pos, due]);
		queueMutex.release();
	}

	/**
		prepares a task for this state, but when the state switches this task will be removed
	**/
	// public static function prepare():WaiterReservation {
	// 	final reserve = new WaiterReservation();
	// 	return reserve;
	// }
 
    public static var pingServer:String;
    static var _elapsedPing:Float = 0;

	public static var waiterReports:String = '';

	function _processQueue(queue:Array<Dynamic>, ?stateBound:Bool = false):Void {
		// Snapshot: tasks enqueued by callbacks run on a later frame, not recursively.
		var limit:Int = Std.int(Math.min(MAX_TASKS_PER_UPDATE, queue.length));
		var generation:Int = stateQueueGeneration;
		for (i in 0...limit) {
			if (stateBound && generation != stateQueueGeneration) break;
			_queueRAW = _shiftQueue(queue);
			if (_queueRAW == null) break;
			_tryQueueCall();
		}
	}

	function _processDelayedQueue():Void {
		var dueTasks:Array<Dynamic> = [];
		var now:Float = haxe.Timer.stamp();
		queueMutex.acquire();
		var i:Int = 0;
		while (i < delayedPersistQueue.length && dueTasks.length < MAX_TASKS_PER_UPDATE) {
			var task = delayedPersistQueue[i];
			if (task[2] <= now) {
				dueTasks.push(task);
				delayedPersistQueue.splice(i, 1);
			} else i++;
		}
		queueMutex.release();

		for (task in dueTasks) {
			_queueRAW = task;
			_tryQueueCall();
		}
	}

	function _shiftQueue(queue:Array<Dynamic>):Dynamic {
		queueMutex.acquire();
		var value = queue.shift();
		queueMutex.release();
		return value;
	}

	function _tryQueueCall() {
		if (_queueRAW == null)
			return;

		_queueCall = cast _queueRAW[0];
		_queueCallPos = cast _queueRAW[1];

		try {
			if (_queueCall != null)
				_queueCall();
		}
		catch (exc) {
			if (_queueCallPos != null)
				waiterReports += 'Called for ${_queueCallPos.className}.${_queueCallPos.methodName} (${_queueCallPos.fileName} line ${_queueCallPos.lineNumber})\n';
			else
				waiterReports += 'Exception in an unlocated Waiter callback\n';
			throw exc;
		}
	}

    override function update(elapsed) {
        super.update(elapsed);

		_processQueue(stateQueue, true);
		_processQueue(persistQueue);
		_processDelayedQueue();

		if (waiterReports.length > 0) {
			waiterReports = '';
		}

		if (pingServer != null) {
			_elapsedPing += elapsed;

            if (_elapsedPing >= 20) {
				_elapsedPing = 0;
				GameClient.getServerPlayerCount(pingServer);
            }
        }
    }
}