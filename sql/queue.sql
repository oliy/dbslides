-----------------
-- Work Queues --
-----------------

-- This is an example efficient transactional queuing structures within Postgres.  
-- Postgres isn't the most efficient/scalable system as a queue, but can handle 
-- a decent volume of queueing as long as the table of queued items is kept 
-- relatively small and vacuumed frequently.  The main issue is reducing the
-- effect of contention on the queue and ensuring assignments are transactional.
--
-- If you have Postgres 9.5+, you can use SKIP LOCKED for simpler implementation
-- with reasonable performance.  For the best performance, you will have to 
-- leverage advisory locks, which have the issue that the lock namespace is
-- globally shared across the database, so you either have to create your
-- own numeric namespace mechanism or ensure your application is the only 
-- application in the database.
--
-- These examples should be used in a concurrent system to properly
-- demonstrate their usefulness.
--
-- There are many other potential considerations and styles of processing a
-- queue in PG.  This reference has a good analysis of many:
--
-- https://johtopg.blogspot.com/2015/01/queues-queues-they-all-fall-down.html


-- Structure of a skelton Queue item
create queue (
    id serial primary key,
    processed timestamp
);


-- generate some data
insert into queue(processed) values (null),(null),(null),(null),(null),(null),(null),(null),(null),(null);


-- Consume item on the queue (SKIP LOCKED)
update queue
-- assign item
set processed = now()
where id in (
  select id
  from queue
  where processed is null
  order by id
  limit 1
  -- skip already locked items
  for update skip locked
)
returning id;


-- Consume item on the queue (ADVISORY LOCK)
update queue
-- assign item
set processed = now()
where id in (
  -- select potential item
  select id
  from (
    select id
    from queue
    where processed is null
    order by id
    -- number of attempts
    limit 5
  ) potential
  -- try to lock
  where pg_try_advisory_lock(id)
  -- deterministic order
  order by id
  limit 1
) 
-- must recheck for MVCC race conditions
and processed is null
returning id;
