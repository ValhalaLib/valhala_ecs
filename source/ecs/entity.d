module ecs.entity;

import std.exception : basicExceptionCtors, enforce;
import std.typecons : Nullable;

version(unittest) import aurorafw.unit.assertion;


/**
 * EntityType is defined as being an integral and unsigned value. Possible
 *     type are **ubyte, ushort, uint, ulong, size_t**. All remaining type are
 *     defined as being invalid.
 *
 * Params: T = type to classify.
 *
 * Returns: true if it's a valid type, false otherwise.
 */
private template isEntityType(T)
{
	import std.traits : isIntegral, isUnsigned;
	enum isEntityType = isIntegral!T && isUnsigned!T;
}

///
@safe
@("entity: isEntityType")
unittest
{
	import std.meta : AliasSeq, allSatisfy;
	assertTrue(allSatisfy!(isEntityType, AliasSeq!(ubyte, ushort, uint, ulong, size_t)));

	assertFalse(allSatisfy!(isEntityType, AliasSeq!(byte, short, int, long, ptrdiff_t)));
	assertFalse(allSatisfy!(isEntityType, AliasSeq!(float, double, real, ifloat, idouble, ireal)));
	assertFalse(allSatisfy!(isEntityType, AliasSeq!(char, dchar, wchar, string, bool)));
}


/**
 * Defines ground constants used to manipulate entities internaly.
 *
 * Constants:
 *     `entityShift` = division point between the entity's **id** and **batch**. \
 *     `entityMask` = bit mask related to the entity's **id** portion. \
 *     `batchMask` = bit mask related to the entity's **batch** portion. \
 *     `entityNull` = Entity!(T) with an **id** of the max value available for T.
 *
 * Code_Gen:
 * | type   | entityShift | entityMask  | batchMask   | entityNull                    |
 * | :------| :---------: | :---------- | :---------- | :---------------------------- |
 * | ubyte  | 4           | 0xF         | 0xF         | Entity!(ubyte)(15)            |
 * | ushort | 8           | 0xFF        | 0xFF        | Entity!(ushort)(255)          |
 * | uint   | 20          | 0xFFFF_F    | 0xFFF       | Entity!(uint)(1_048_575)      |
 * | ulong  | 32          | 0xFFFF_FFFF | 0xFFFF_FFFF | Entity!(ulong)(4_294_967_295) |
 *
 * Sizes:
 * | type   | id-(bits) | batch-(bits) | max-entities  | batch-reset   |
 * | :----- | :-------: | :----------: | :-----------: | :-----------: |
 * | ubyte  | 4         | 4            | 14            | 15            |
 * | ushort | 8         | 8            | 254           | 255           |
 * | uint   | 20        | 12           | 1_048_574     | 4_095         |
 * | ulong  | 32        | 32           | 4_294_967_295 | 4_294_967_295 |
 *
 * Params: T = valid entity type.
 */
private mixin template genBitMask(T)
	if (isEntityType!T)
{
	static if (is(T == uint))
	{
		enum T entityShift = 20U;
		enum T entityMask = (1UL << 20U) - 1;
		enum T batchMask = (1UL << (T.sizeof * 8 - 20U)) - 1;
	}
	else
	{
		enum T entityShift = T.sizeof * 8 / 2;
		enum T entityMask = (1UL << T.sizeof * 8 / 2) - 1;
		enum T batchMask = (1UL << (T.sizeof * 8 - T.sizeof * 8 / 2)) - 1;
	}

	enum Entity!T entityNull = Entity!T(entityMask);
}

///
@safe
@("entity: genBitMask")
unittest
{
	{
		mixin genBitMask!uint;
		assertTrue(is(typeof(entityShift) == uint));

		assertEquals(20, entityShift);
		assertEquals(0xFFFF_F, entityMask);
		assertEquals(0xFFF, batchMask);
		assertEquals(Entity!uint(entityMask), entityNull);
	}

	{
		mixin genBitMask!ulong;
		assertTrue(is(typeof(entityShift) == ulong));

		assertEquals(32, entityShift);
		assertEquals(0xFFFF_FFFF, entityMask);
		assertEquals(0xFFFF_FFFF, batchMask);
		assertEquals(Entity!ulong(entityMask), entityNull);
	}
}


class MaximumEntitiesReachedException : Exception { mixin basicExceptionCtors; }


/**
 * Defines an entity of entity type T. An entity is defined by an **id** and a
 *     **batch**. It's signature is the combination of both values. The first N
 *     bits belong to the **id** and the last M ending bits to the `batch`. \
 * \
 * An entity in it's raw form is simply a value of entity type T formed by the
 *     junction of the id with the batch. The constant values which define all
 *     masks are calculated in the `genBitMask` mixin template. \
 * \
 * An entity is then defined by: **id | (batch << entity_shift)**. \
 * \
 * Let's imagine an entity of the ubyte type. By default it's **id** and **batch**
 *     occupy **4 bits** each, half the sizeof ubyte. \
 * \
 * `Entity!ubyte` = **0000 0000** = ***(batch << 4) | id***.
 * \
 * What this means is that for a given value of `ubyte` it's first half is
 *     composed with the **id** and it's second half with the **batch**. This
 *     allows entities to be reused at some time in the program's life without
 *     having to resort to a more complicated process. Every time an entity is
 *     **discarded** it's **id** doesn't suffer any alterations however it's
 *     **batch** is increased by **1**, allowing the usage of an entity with the
 *     the same **id** but mantaining it's uniqueness with a new **batch**
 *     generating a completely new signature.
 *
 * See_Also: [skypjack - entt](https://skypjack.github.io/2019-05-06-ecs-baf-part-3/)
 */
@safe
struct Entity(T)
	if (isEntityType!T)
{
public:
	this(in T id) { _id = id; }
	this(in T id, in T batch) { _id = id; _batch = batch; }

	bool opEquals(in Entity other) const
	{
		return other.signature == signature;
	}

	@property
	T id() const { return _id; }

	@property
	T batch() const { return _batch; }

	auto incrementBatch()
	{
		_batch = _batch >= EntityManager!(T).batchMask ? 0 : cast(T)(_batch + 1);

		return this;
	}

	T signature() const
	{
		return cast(T)(_id | (_batch << EntityManager!(T).entityShift));
	}

private:
	T _id;
	T _batch;
}

@safe
@("entity: Entity")
unittest
{
	auto entity0 = Entity!ubyte(0);

	assertEquals(0, entity0.id);
	assertEquals(0, entity0.batch);
	assertEquals(0, entity0.signature);
	assertEquals(Entity!ubyte(0, 0), entity0);

	entity0.incrementBatch();
	assertEquals(0, entity0.id);
	assertEquals(1, entity0.batch);
	assertEquals(16, entity0.signature);
	assertEquals(Entity!ubyte(0, 1), entity0);

	entity0 = Entity!ubyte(0, 15);
	entity0.incrementBatch();
	assertEquals(0, entity0.batch); // batch reseted

	assertEquals(15, Entity!ubyte(0, 15).batch);
}


/**
 * Responsible for managing all entities lifetime and access to components as
 *     well as any operation related to them.
 *
 * Params: T = valid entity type.
 */
class EntityManager(T)
{
public:
	mixin genBitMask!T;


	this() { queue = entityNull; }


	/**
	 * Generates a new entity either by fabricating a new one or by recycling an
	 *     previously fabricated if the queue is not null. Throws a
	 *     **MaximumEntitiesReachedException** if the amount of entities alive
	 *     allowed reaches it's maximum value.
	 *
	 * Returns: a newly generated Entity!T.
	 *
	 * Throws: `MaximumEntitiesReachedException`.
	 */
	@safe
	Entity!(T) gen()
	{
		return queue.isNull ? fabricate() : recycle();
	}


	/**
	 * Makes a valid entity invalid. When an entity is discarded it's **swapped**
	 *     with the current entity in the **queue** and it's **batch** is
	 *     incremented. The operation is aborted when trying to discard an
	 *     invalid entity.
	 *
	 * Params: entity = valid entity to discard.
	 *
	 * Returns: true if successful, false otherwise.
	 */
	@safe
	bool discard(in Entity!(T) entity)
	{
		// Invalid action if the entity is not valid
		if (!(entity.id < entities.length && entities[entity.id] == entity))
			return false;

		entities[entity.id] = queue.isNull ? entityNull : queue ; // move the next in queue to back
		queue = entity;                                           // update the next in queue
		queue.incrementBatch();                                   // increment batch for when it's revived
		return true;
	}

private:
	/**
	 * Creates a new entity with a new id. The entity's id follows the total
	 *     value of entities created. Throws a **MaximumEntitiesReachedException**
	 *     if the maximum amount of entities allowed is reached.
	 *
	 * Returns: an Entity!T with a new id.
	 *
	 * Throws: `MaximumEntitiesReachedException`.
	 */
	@safe
	Entity!(T) fabricate()
	{
		import std.format : format;
		enforce!MaximumEntitiesReachedException(
			entities.length < entityMask,
			format!"Reached the maximum amount of entities supported for type %s: %s!"(T.stringof, entityMask)
		);

		import std.range : back;
		entities ~= Entity!(T)(cast(T)entities.length); // safe cast
		return entities.back;
	}


	/**
	 * Creates a new entity reusing a **previously discarded entity** with a new
	 *     **batch**. Swaps the current discarded entity stored the queue's entity
	 *     place with it.
	 *
	 * Returns: an Entity!T previously fabricated with a new batch.
	 */
	@safe
	Entity!(T) recycle()
		in (!queue.isNull)
	{
		immutable next = queue;     // get the next entity in queue
		queue = entities[next.id];  // grab the entity which will be the next in queue
		entities[next.id] = next;   // revive the entity
		return next;
	}


	Entity!(T)[] entities;
	Nullable!(Entity!(T), entityNull) queue;
}


@safe
@("entity: EntityManager")
unittest
{
	assertTrue(__traits(compiles, EntityManager!uint));
	assertFalse(__traits(compiles, EntityManager!int));
}

@safe
@("entity: EntityManager: discard")
unittest
{
	auto em = new EntityManager!uint();
	assertTrue(em.queue.isNull);

	auto entity0 = em.gen();
	auto entity1 = em.gen();
	auto entity2 = em.gen();


	em.discard(entity1);
	assertFalse(em.queue.isNull);
	assertEquals(em.entityNull, em.entities[entity1.id]);
	(() @trusted => assertEquals(Entity!uint(1, 1), em.queue))(); // batch was incremented

	assertTrue(em.discard(entity0));
	assertEquals(Entity!uint(1, 1), em.entities[entity0.id]);
	(() @trusted => assertEquals(Entity!uint(0, 1), em.queue))(); // batch was incremented

	// cannot discard invalid entities
	assertFalse(em.discard(Entity!uint(50)));
	assertFalse(em.discard(Entity!uint(entity2.id, 40)));

	assertEquals(3, em.entities.length);
}

@safe
@("entity: EntityManager: fabricate")
unittest
{
	import std.range : back;
	auto em = new EntityManager!ubyte();

	auto entity0 = em.gen(); // calls fabricate
	em.discard(entity0); // discards
	em.gen(); // recycles
	assertTrue(em.queue.isNull);

	assertEquals(Entity!(ubyte)(1), em.gen()); // calls fabricate again
	assertEquals(2, em.entities.length);
	assertEquals(Entity!(ubyte)(1), em.entities.back);

	em.entities.length = 15; // max entities allowed for ubyte
	expectThrows!MaximumEntitiesReachedException(em.gen());
}

@safe
@("entity: EntityManager: gen")
unittest
{
	import std.range : front;
	auto em = new EntityManager!uint();

	assertEquals(Entity!(uint)(0), em.gen());
	assertEquals(1, em.entities.length);
	assertEquals(Entity!(uint)(0), em.entities.front);
}

@safe
@("entity: EntityManager: recycle")
unittest
{
	import std.range : front;
	auto em = new EntityManager!uint();

	auto entity0 = em.gen(); // calls fabricate
	em.discard(entity0); // discards
	(() @trusted => assertEquals(Entity!uint(0, 1), em.queue))(); // batch was incremented
	assertFalse(Entity!uint(0, 1) == entity0); // entity's batch is not updated

	entity0 = em.gen(); // recycles
	assertEquals(Entity!uint(0, 1), em.entities.front);
}