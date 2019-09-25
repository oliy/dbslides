------------------------------
-- JSONB vs EAV Performance --
------------------------------

-- This example explores techniques for modeling custom data/attributes for
-- entities.  EAV (Entity Attribute Value) stores each key/value pais in
-- a separate, linked table, while JSONB uses PG's custom storage model for
-- JSON.  In addition, PG also has HStore, which should have similar 
-- performance


-- JSONB shows almost 10x performance


-- JSONB index structure
drop table if exists test_json;
create table test_json (
  id serial primary key, 
  data jsonb
);
-- create index ix_test_json on test_json using gin(data jsonb_path_ops);

-- Entity Attribute Value structure
drop table if exists test_eav;
create table test_eav (
  id int, 
  attr int, 
  val text
);
-- create index ix_test_eav on test_eav (id, attr);
-- create index ix_test_eav2 on test_eav (attr, val);


-- Generate Test Data

-- use deterministic random seed, for easier references
select setseed(0.5);

-- Generate Random Attribute/Value pairs
insert into test_eav
select
  (random() * 100000)::int as id, (random() * 100)::int as attr, ((random() * 1000)::int)::text as val
from generate_series(1, 1000000);

-- Generate equivalent JSON
insert into test_json
select id, jsonb_object_agg(attr, val)
from test_eav
group by id;

create index ix_test_json on test_json using gin(data jsonb_path_ops);
-- create index ix_test_json on test_json using gin(data jsonb_ops);
create index ix_test_eav on test_eav (id,attr);
create index ix_test_eav2 on test_eav (attr, val);

-- Use case of EAV search
explain analyze 
select * from test_eav where id in (
  select foo.id from test_eav foo, test_eav bar
  where foo.id = bar.id
  and foo.attr = 51 and foo.val='781'
  and bar.attr = 8 and bar.val='198'
);

-- Usage case of indexed JSON search  
explain analyze 
select data from test_json where data @> '{"51":"781", "8":"198"}'::jsonb;


-- Bonus
drop table if exists test_hstore;
create table test_hstore (
  id int,
  data hstore
);

insert into test_hstore
select id, hstore(array_agg(atrt,val))
from test_eav
group by id;

create index ix_test_hstore on test_hstore using gin(data);
