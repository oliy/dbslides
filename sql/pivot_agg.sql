-----------------------
-- Pivot Aggregation --
-----------------------

-- Simple trick of separating out different categories of aggregations
-- into columns by collapsing rows and using 0/nil to skip categories.

-- Sample datastructure
drop table if exists sample;
create table sample (
  id serial primary key,
  ts timestamptz not null default now(),
  type text not null,
  metric int not null
);

-- Sample Data
insert into sample(type,metric) values 
  ('apple',4),
  ('orange',2),
  ('banana',3),
  ('apple',5),
  ('banana',2),
  ('apple',1),
  ('orange',2)
;

-- Sample Pivot Aggregation
select 
  sum(case when type='apple' then metric else 0 end) as apple, 
  sum(case when type='orange' then metric else 0 end) as orange, 
  sum(case when type='banana' then metric else 0 end) as banana
from sample;
