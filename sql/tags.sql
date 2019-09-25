----------------------
-- Tag Cloud Models --
----------------------

-- Experiment to help explore and evaluate the performance of different 
-- solutions to supporting tagging of rows in Postgres.
--
-- Summary:
--
-- IntArrays provide the most performance/features/size at the cost of
-- a bit of indirection/complexity.  It supports generalized boolean
-- expression queries & fast lookup, as long as everything is expressed
-- in ids.
--
-- The StringArray is the most direct and simple to use and has fairly
-- decent performance in most cases.
--
-- JSONB works ok: performance for some cases are slower and takes more 
-- space, but it supports key/values in addition to pure tags/labels.


-- Simple Array of Strings

drop table if exists doc;
create table doc (
  id int primary key,

  -- array of tag strings
  tags text[] not null
);
-- Index for array operations
-- create index doc_tags on doc using gin(tags);


-- Normalized Tags with IntArray

-- required extension
create extension if not exists intarray;
  
-- denormalize tag table
drop table if exists tags;
create table tags (
  id serial primary key,
  tag text not null
);
-- create unique index tags_tag on tags(tag);

-- documents with array of tag indices
drop table if exists doc_int;
create table doc_int (
  id serial primary key,

  -- intarray
  tag_ids int[] not null
);
-- Specialized index from intarray extension
-- create index doc_int_tagids on doc_int using gin(tag_ids gin__int_ops);


-- JSONB dictionaries for Tags

drop table if exists doc_json;
create table doc_json (
  id serial primary key,

  -- jsonb with keys as tags
  tags jsonb not null
);
-- Specalized JSON index for faster membership operations
-- create index doc_json_tags on doc_json using gin(tags jsonb_path_ops);



-- Generate data for testing
-- 1. First generates normalized tag table & docs
-- 2. Populate denormalized tag arrays
-- 3. Populate JSON tags

-- Generate Tag names
insert into tags(tag)
select 'Tag_' || i::text
from generate_series(1,1000) s(i);

-- create tag index
create unique index tags_tag on tags(tag);

-- Generate Test Docs & Tags
insert into doc_int(tag_ids)
select (
  select 
    -- tag value geometric distribution to max tag value
    array_agg(ceiling(1000.0*least(1.0,log(random())/log(0.001)))::int)
  -- number of tags geometric distribution
  from generate_series(1,ceiling(1000.0*least(1.0,log(random())/log(0.001)))::int+i*0)
)
-- number of docs
from generate_series(1,100000) s(i);

-- create index after bulk insert
create index doc_int_tagids on doc_int using gin(tag_ids gin__int_ops);


-- Copy into denormalized text arrays
insert into doc
select d.id, array_agg(t.tag)
from doc_int d, unnest(tag_ids) as i(tag_id)
join tags t on t.id = i.tag_id
group by d.id;

-- index doc tags
create index doc_tags on doc using gin(tags);


-- Copy into jsonb docs
insert into doc_json
select id, jsonb_object_agg(name, val) as tags from (
  select d.id, unnest(d.tags) as name, true as val
  from doc d
) rs
group by id;

-- index json
create index doc_json_tags on doc_json using gin(tags jsonb_path_ops);



-- Simple Query Tests
explain analyze 
select id from doc where (tags @> ARRAY['Tag_51','Tag_102','Tag_52']);

explain analyze 
select id from doc_int where tag_ids @> ARRAY[51,102,52];

explain analyze 
select id from doc_json where tags @> '{"Tag_51":true,"Tag_102":true,"Tag_52":true}';

-- Compound Query Tests
explain analyze 
select id from doc where (tags @> ARRAY['Tag_51'] OR (tags @> ARRAY['Tag_102','Tag_52'])) AND NOT tags @> ARRAY['Tag_10'];

explain analyze 
select id from doc_int where tag_ids @@ '(51|(102&52))&!10';

explain analyze 
select id from doc_json where (tags @> '{"Tag_51":true}' OR tags @> '{"Tag_102":true,"Tag_52":true}') AND NOT tags @>'{"Tag_10":true}';

