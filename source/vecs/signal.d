module vecs.signal;

version(vecs_unittest) import aurorafw.unit.assertion;

struct Signal(T ...)
{
	alias SlotType = void delegate(T);
	alias SlotTypeRef = void delegate(ref T);

	@safe pure nothrow
	void connect(SlotType slot)
	{
		slots ~= slot;
	}

	@safe pure nothrow
	void disconnect(SlotType slot)
	{
		import std.algorithm : countUntil;
		auto index = slots.countUntil(slot);
		if (index != -1)
		{
			slots = slots[0 .. index] ~ slots[index+1 .. $];
		}
	}

	@system
	void emit(T args)
	{
		foreach (ref slot; slots) {
			slot(args);
		}
	}

	SlotType[] slots;
}

@system
@("signal: empty")
unittest
{
	Signal!() sig; // empty signal
	size_t num;
	auto fun = () { num++; };

	sig.connect(fun);
	sig.emit();
	assertEquals(1, num);

	sig.disconnect(fun);
	sig.emit();
	assertEquals(1, num);
}

@system
@("signal: different instances having the same Signal type")
unittest
{
	Signal!(int) sigA;
	Signal!(int) sigB;
	size_t num;

	sigA.connect((int x) { num = x; });
	sigB.connect((int x) { num += x; });

	sigA.emit(4);
	sigB.emit(16);
	assertEquals(20, num);
}

@system
@("signal: using a function")
unittest
{
	import std.functional : toDelegate;
	Signal!(size_t*) sig;
	size_t num;

	auto fun = function(size_t* n) { (*n)++; };
	sig.connect(toDelegate(fun));

	sig.emit(&num);
	assertEquals(1, num);
}
