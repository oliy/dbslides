-----------------------------------------------
-- Directed Acyclic Graph/Transitive Closure --
-----------------------------------------------

-- This example explores Node/Edge style graph structures and efficient
-- mechanisms to scale it's use for large datasets.  More specifically
-- we explore explicitly saving the transitive closure of the graph
-- (which means that every node is linked to all of it's descendants,
-- not just it's direct children.)  Having transitive closure trades off
-- storage space for the ability to load the complete tree in 1 
-- roundtrip/query to the databse.  For the common case of numerous,
-- but relatively shallow trees, transitive closure is feasible.  If
-- you need to model deep/wide trees, this may get expensive, since
-- it's generally a combinatoric explosion with respect to tree depth.
-- A common optimization is to only have transitive closure between
-- connecting nodes and not terminal nodes (i.e. separate Groups 
-- from individual members.

-- Structure for nodes
drop table if exists nodes;
create table nodes (
  id serial primary key,
  name text unique not null
);

-- Structure for links
drop table if exists deps;
create table deps (
  parent int not null,
  child int not null,
  indirect boolean not null default false,
  primary key (parent, child)
);


-- Generate data from raw NPM example
insert into nodes(name)
select parent from dep_list
union
select child from dep_list;

insert into deps (parent,child)
select distinct n1.id, n2.id 
from dep_list d
inner join nodes n1 on n1.name = d.parent
inner join nodes n2 on n2.name = d.child; 


-- Generate Transitive Closure on Top level entity
-- (i.e. generate all indirect relationships)
with recursive link_all(parent,child) as (
  -- Base case of direct children of root node
  select d.parent, d.child
  from deps d
  inner join nodes n on n.id = d.parent
  where n.name = 'dbslides'

  union all

  -- Add all linkages to next level of descendants
  select distinct node as parent, d.child
  from link_all l, unnest(ARRAY[l.parent,l.child]) as node, deps d
  where d.parent = l.child
)
-- Only add links that are not already included (direct links)
--   so remaining ones are indirect links
insert into deps
select distinct parent, child, true
from link_all l
where not exists (
  select 1 
  from deps d 
  where d.parent = l.parent and d.child = l.child
);


-- show that we now have linkages to all nodes in the graph from the root
select count(*) from nodes;

select count(*) from deps 
where parent=(
  select id from nodes where name = 'dbslides'
);

-- Explore Sub Groups
select disctinct name 
from deps 
inner join nodes on id = child
where parent = (
  select id from nodes where name = 'yargs'
);
