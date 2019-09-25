----------------------
-- Pivoting Example --
----------------------

-- Simple trick for converting EAV style data into Table data

-- Structure/"row" for entities
drop table if exists entities;
create table entities (
  id serial primary key,
  name varchar
);

-- Entity, Attribute, Value table
drop table if exists eav;
create table eav (
  id int not null,
  key varchar not null,
  str text,
  num int,
  flag bool
);

-- Create Sample data
insert into entities(name) values ('foo'),('bar');
insert into eav(id,key,str)  values (1,'alias','fu');
insert into eav(id,key,num)  values (1,'score',5);
insert into eav(id,key,flag) values (1,'test',true);
insert into eav(id,key,str)  values (2,'alias','baz');
insert into eav(id,key,num)  values (2,'score',7);
insert into eav(id,key,flag) values (3,'test',false);

-- Example Pivot
select 
  entities.*,
  -- slice eav table for each column, 
  -- using max to coalesce values across eav rows
  max(case when key='alias' then str end) as alias,
  max(case when key='score' then num end) as score,
  bool_or(case when key='test' then flag end) as flag
from entities
left outer join eav on entities.id = eav.id
group by entities.id, entities.name
order by entities.id
;

