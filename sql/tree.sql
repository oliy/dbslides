-----------------
-- Tree Models --
-----------------

-- Experiment to show relative performance of materialized path vs interval 
-- trees (nested sets) for modeling hierarchies in postgres.  For intervals, 
-- we take advantage of Postgres specific functions to handle ranges.
--
-- Summary:
--
-- Materialized paths are more expensive spacewise, but are so much easier
-- to understand/use and computationally decent that it's probably not
-- worth using interval trees in all but very specialized optimizations.
-- For a common case of names in paths, like modeling a filesystem, often
-- using the full path as a string is also often faster than the Arrays
-- of IDs approach.


-- Structure of a Materialized Path table
--   Each node has a path that represents the path from the root node.
--   The path can include itself, for a complete path, or just the ancestors.
drop table if exists tree;
create table tree (
  id serial primary key,
  path integer[] not null
);
-- create index tree_path on tree using gin(path);


-- Generate Test Children from a set of nodes
create or replace function generate_leaves(lower int, upper int, num int, children int) returns void as $$
  insert into tree(path)
  select array_append(tree.path, tree.id)
  from (
    select * from tree where id between lower AND upper order by random() limit num
  ) tree, generate_series(1,children);
$$ language sql;

-- Generate top level children, deterministically
insert into tree(path)
select '{}'::int[]
from generate_series(1,10) s(i);

insert into tree(path)
select array_append(tree.path, tree.id)
from generate_series(1,9) s(i), tree;

-- Generate next level of children
select generate_leaves(11,100,90,10);
select generate_leaves(101,1000,500,18);
select generate_leaves(1001,10000,5000,18);
-- select generate_leaves(10001,100000,50000,18);
-- select generate_leaves(100001,1000000,500000,18);

create extension if not exists intarray;
create index tree_path on tree using gin(path gin__int_ops);

-- Sample Query on sub-tree of elements
explain analyze 
select count(*)
from tree
where path @> array[2,22];


-- Structure of Materialized Path as string path
--   Simpler queries if path includes it's own id.
--   Note, use text_pattern_ops, to ensure that we can properly search
drop table if exists tree_text;
create table tree_text (
  id serial primary key,
  path text not null
);
-- create index tree_text_path on tree_text(path text_pattern_ops);


-- Convert test data to path strings
insert into tree_text(path)
select array_to_string(array_append(path,id),'/')
from tree;

create index tree_text_path on tree_text(path text_pattern_ops);

-- Sample Query on a Full sub-tree of elements
explain analyze 
select count(*) 
from tree_text
where path like '2/22/%';



--  Nested Set implementation with Range Type
--  Yields a modest speed increase, but much more complicated to maintain
--
--  Nested Sets linearizes the complete space into a set of numeric values
--    and represents a parent as the range (min, max) that contains all
--    child ranges.  We can use the Postgres range type/index for optimizing
--    range queries.  Normally, maintenance of the ranges would be executed
--    at insertion/deletion time for log(N) operations to update all
--    ancestors of a new leaf.

drop table if exists tree_int;
create table tree_int (
  id serial primary key,
  pos int4range not null
);
-- create index tree_int_pos on tree_int using gist(pos);

-- Convert Test data to Interval Trees
-- Note: This code is particularly ugly, to avoid logarithmic time to build.
--   After sorting (O(n log n) time), there's a nice linear time algorithm 
--   for assigning the intervals, but it would require procedural SQL for
--   legibility.  Normally, the interval tree would probably be maintained
--   through updating parent intervals incrementally after insertion.
rollback;
begin;

-- build absolute ordering
create temp table tree_tmp
on commit drop as
select 
  id, 
  path,
  parent,
  (row_number() over (order by path))::int4 as pos,
  (row_number() over (order by path))::int4 as r
from (
  select 
    id, 
    array_append(path, id) as path,
    path[array_upper(path,1)] as parent
  from tree
) t;

-- Build up a layer of ranges.  (repeat until no rows are updated)
create or replace function bracket() returns void as $$
  update tree_tmp t
  set r=rmax.r 
  from (
    select parent, max(r) as r from tree_tmp group by parent
  ) rmax
  where t.id = rmax.parent
  and t.r<rmax.r;
$$ language sql;

-- make sure we roll up ranges enough times.
select bracket();
select bracket();
select bracket();
select bracket();
select bracket();
select bracket();

-- save final ranges
insert into tree_int(id, pos)
select id, int4range(pos,r,'[]') 
from tree_tmp;

commit;

create index tree_int_pos on tree_int using gist(pos);

-- Sample Query on a Full sub-tree of elements (includes the node itself)
explain analyze 
select count(*)
from tree_int
where (select pos from tree_int where id = 22) @> pos; 
