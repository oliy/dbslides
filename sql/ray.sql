--------------------------------------------
-- Recursive Ray Tracer in SQL (Postgres) --
--------------------------------------------

-- This crazy experiment attempts to implement a recursive ray tracer
-- with general SQL statements (i.e. avoiding specialized stored
-- procedures that implement the logic procedurally, like a regular
-- low level implementation language.)  Practically, though, optimized 
-- procedural forms are included to significantly reduce the runtime to 
-- avoid wasting TOO much time while generating sample images, but the 
-- original general SQL forms should provide equivalent images.
--
-- This ray tracer broadly follows the Ray Tracing in a Weekend series:
--   https://github.com/RayTracing/InOneWeekend
-- And implements diffuse and metal material models.  To change the scene,
-- you can change the data in the things or cameras tables.

-- To use this script, you need to adjust the output to remove blank lines:
--   psql <auth options> -f sql/ray.sql -q -At | grep -v '^$' > output.ppm
--
-- This generates the output.ppm file, which you can read into image viewers or
-- use conversion tools (like ppm2tiff).


-- Vector Type/Functions (reusable!)
-- 
-- Note: ok, so using custom types and stored procedures are sort of bending
--   the rules a but, but custom types are fairly standard across many
--   major SQL implementations and I'm using general SQL in the stored
--   procs that could be expanded to regular SQL.  This just saves a whole
--   bunch of boilerplate to preserve the sanity of the author.

drop type if exists vec3 cascade;
create type vec3 as (x float, y float, z float);

create or replace function add(a vec3, b vec3) returns vec3 as $$
  select a.x+b.x, a.y+b.y, a.z+b.z;
$$ language sql;

create or replace function sub(a vec3, b vec3) returns vec3 as $$
  select a.x-b.x, a.y-b.y, a.z-b.z;
$$ language sql;

create or replace function mul(a vec3, f float) returns vec3 as $$
  select a.x*f, a.y*f, a.z*f;
$$ language sql;

create or replace function div(a vec3, f float) returns vec3 as $$
  select a.x/f, a.y/f, a.z/f;
$$ language sql;

create or replace function scale(a vec3, b vec3) returns vec3 as $$
  select a.x*b.x, a.y*b.y, a.z*b.z;
$$ language sql;

create or replace function cross(a vec3, b vec3) returns vec3 as $$
  select a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x;
$$ language sql;

create or replace function dot(a vec3, b vec3) returns float as $$
  select a.x*b.x + a.y*b.y + a.z*b.z;
$$ language sql;

create or replace function length(a vec3) returns float as $$
  select sqrt(a.x*a.x + a.y*a.y + a.z*a.z);
$$ language sql;

create or replace function length2(a vec3) returns float as $$
  select a.x*a.x + a.y*a.y + a.z*a.z;
$$ language sql;

create or replace function unit(a vec3) returns vec3 as $$
  select div(a, length(a));
$$ language sql;

create or replace function reflect(a vec3, n vec3) returns vec3 as $$
  select sub(a,mul(n, dot(a,n)*2.0));
$$ language sql;

create or replace function rand_sphere() returns vec3 as $$
  select unit((random()-0.5,random()-0.5,random()-0.5));
$$ language sql;


-- Ray Type/Functions
drop type if exists ray cascade;
create type ray as (p vec3, dir vec3);

create or replace function ray_at(r ray, t float) returns vec3 as $$
  select add(r.p,mul(r.dir, t));
$$ language sql;


-- Shapes (spheres) interection detection

drop type if exists hit_record cascade;
create type hit_record as (t float, p vec3, n vec3);

-- check ray/sphere intersection (pure PG sql), using quadratic equation
create or replace function hit_sphere(center vec3, radius float, r ray) returns hit_record as $$
  with
    tmp1 as (select 
      sub(r.p, center) oc
    ),
    tmp2 as (select 
      length2(r.dir) a,
      dot(oc,r.dir) as b,
      length2(oc) - radius*radius as c
    from tmp1),
    tmp3 as (select 
      b*b - a*c as d 
    from tmp1,tmp2),
    tmp4 as (select 
      case 
        when d>0.0 then (-b - sqrt(d))/a
        else -1.0
      end as t
    from tmp2,tmp3),
    tmp5 as (select
      t,
      ray_at(r, t) as p
    from tmp4)
  select t, p, div(sub(p,center), radius) as n from tmp5
$$ language sql;

-- more optimized plpgsql ray/sphere for saner rendering times
-- Note: can comment this one out for pure non-procedural version
create or replace function hit_sphere(center vec3, radius float, r ray) returns hit_record as $$
  declare
    oc vec3;
    a float;
    b float;
    c float;
    d float;
    t float;
    p vec3;
  begin
    oc := sub(r.p, center);
    a := length2(r.dir);
    b := dot(oc,r.dir);
    c := length2(oc) - radius*radius;
    d := b*b - a*c;
    if d>0.0 then 
      t := (-b - sqrt(d))/a;
      p := ray_at(r, t);
      return (t, p, div(sub(p,center), radius))::hit_record;
    else 
      return (-1, r.p, r.dir)::hit_record;
    end if;
  end
$$ language plpgsql;

-- Things to see (hard code spheres, for now)
drop table if exists things;
create table things (
  id serial primary key,
  p vec3 not null,
  radius float not null,
  col vec3 not null,
  fuzz float not null
);

-- Location/colors of actual spheres
insert into things (p,radius,col,fuzz) values
  ((0,-500,0),500, (0.5,0.5,0.5), 0.8),
  ((0,0.5,0),0.5, (0.9,0.9,0.9), 0.0),
  ((1,0.5,0),0.5, (0.8,0.2,0.2), 1.2),
  ((-1,0.5,0),0.5, (0.9,0.9,0.1), 0.2),
  ((0.9,0.1,0.9),0.1, (0.3,0.4,0.5), 0.8),
  ((-0.1,0.25,1.2),0.25, (0.1,0.6,0.2), 0.0),
  ((0.1,0.17,0.7),0.17, (0.5,0.2,0.6), 0.5)
;


-- Recursive Ray casting
create or replace function camera(r0 ray) returns vec3 as $$
  with recursive camera(r, depth, color) as (
    -- initial camera ray
    select r0, 20, (1,1,1)::vec3
    union all 
    select * 
    from (
      with
        cam as (select r, depth, color from camera), 
        -- find first intersection with things
        raycast as (
          select *
          from (select hit_sphere(p, radius, r) hit, col, fuzz from things, cam) tthings
          where (hit).t>0.001
          order by (hit).t
          limit 1
        )
      select
        case when depth>1 and exists (select 1 from raycast) then (
          -- hit a surface, calculate secondary raycast, uncomment one of the 2 lighting models
          -- diffuse/lambert shading
          -- select ((hit).p, add((hit).n, rand_sphere()))::ray from raycast
          -- reflective/metal shading
          select ((hit).p, add(reflect((r).dir, (hit).n), mul(rand_sphere(),fuzz)))::ray from raycast
        )
        else
          -- over maximum reflections, leave original ray
          r
        end,
        case when depth>1 and exists (select 1 from raycast) then 
          -- adjust depth for next raycast
          depth-1
        else 
          0
        end,
        case when depth>1 and exists (select 1 from raycast) then (
          -- combine material color with secondary raycast color
          select scale(color,(select col from raycast))
        )
        else (
          -- calculate color as sky color
          select scale(add(mul((1,1,1),1.0 - t2), mul((0.5,0.7,1.0),t2)), color)
          from (select 0.5*(unit((r).dir)).y + 1.0 t2) as tmp
        )
        end
      from cam
      where
        depth>0
    ) tmp
  )
  -- only return final color result
  select color from camera
  where depth=0
$$ language sql;


-- more optimized (and clearer) plpgsql raycaster
create or replace function cam(r ray, depth float) returns vec3 as $$
  declare
    raycast record;
    r2 ray;
    t2 float;
  begin
    if depth<= 0 then
      -- early return for too many reflections
      return (0,0,0)::vec3;
    end if;
    -- find first intersection with things
    select *
      into raycast
      from (select hit_sphere(p, radius, r) hit, col, fuzz from things) tthings
      where (hit).t>0.001
      order by (hit).t
      limit 1;
    if raycast.hit is not null then
      -- hit a surface, calculate secondary raycast, uncomment one of the 2 lighting models
      -- diffuse/lambert shading
      -- r2 := ((raycast.hit).p, add((raycast.hit).n, rand_sphere()))::ray;
      -- reflective/metal shading
      r2 := ((raycast.hit).p, add(reflect(r.dir, (raycast.hit).n), mul(rand_sphere(), raycast.fuzz)))::ray;
      return scale(raycast.col, cam(r2, depth+1));
    else
      -- calculate color as sky color
      t2 := 0.5*(unit((r).dir)).y + 1.0;
      return add(mul((1,1,1),1.0 - t2), mul((0.5,0.7,1.0),t2));
    end if;
  end
$$ language plpgsql;

-- Note: can comment this one out for pure non-procedural version
create or replace function camera(r0 ray) returns vec3 as $$
  select (cam(r0, 20));
$$ language sql;

-- Camera Views
drop table if exists cameras;
create table cameras (
  id serial primary key,
  nx int default 50,
  ny int default 50,
  ns int default 1,
  jitter float default 0.0,
  origin vec3 default (0,0,0),
  vx vec3 default (1,0,0),
  vy vec3 default (0,1,0),
  vz vec3 default (0,0,-1)
);

-- camera setup
-- 
-- given a target target location, eye location, and image size/sampling parameters
-- generate camera view constants.
create or replace function look_at(target_id int, width int, height int, subsampling int, jit float, origin0 vec3, target vec3, screen float) returns void as $$
  with 
    tmp2 as (select 
      width::float/height::float as aspect,
      sub(origin0, target) as vz
    ),
    tmp3 as (select *,
      mul(unit(cross((0,1,0), vz)), aspect*screen) as vx
    from tmp2),
    up as (select *,
      mul(unit(cross(vz, vx)), screen) as vy
    from tmp3)
  insert into cameras(id, origin, vx, vy, vz, nx, ny, ns, jitter) 
    select target_id, origin0, up.vx, up.vy, up.vz, width, height, subsampling, jit from up;

--  select vz from cameras where id=target_id;
$$ language sql;


-- different camera views
select look_at(1, 60,40, 1,1.0, (1.0,1.5,3.0), (0,0.2,0), 2.0);  -- 2/5 seconds
select look_at(2, 150,100, 1,0.0, (1.0,1.5,3.0), (0,0.2,0), 2.0);  -- 20/60 seconds
select look_at(3, 60,40, 2,0.0, (1.0,1.5,3.0), (0,0.2,0), 2.0);
select look_at(4, 30,20, 5,1.0, (1.0,1.5,3.0), (0,0.2,0), 2.0);  -- 10/30 sec
select look_at(5, 300,200, 1,0.0, (1.0,1.5,3.0), (0,0.2,0), 2.0);
select look_at(6, 300,200, 3,0.0, (1.0,1.5,3.0), (0,0.2,0), 2.0);
select look_at(7, 640,480, 4,1.0, (1.0,1.5,3.0), (0,0.2,0), 2.0);  -- 3 hours


-- Color conversion (vec3 to PPM pixel)
create or replace function color(col vec3) returns text as $$
  select (floor(sqrt(col.x) * 255.9))::int || ' ' || (floor(sqrt(col.y) * 255.9))::int || ' ' || (floor(sqrt(col.z) * 255.9))::int
$$ language sql;


-- Generate PPM Image
with 
  -- select camera (change camera id to choose view)
  params as (select * from cameras where id = 1),
  -- generate image matrix
  view as (
    select u::float as u, v::float as v 
    from generate_series(0,(select ny from params)-1) v
    cross join generate_series(0,(select nx from params)-1) u
  ),
  -- calculate pixel values
  pixels as (
    select (
      -- combine subsampled values per pixel
      select (avg((sample).x), avg((sample).y), avg((sample).z))::vec3 as pixel
      from (
        -- subsample in a grid (ns x ns) with proportional jitter 
        select camera((
          origin,
          sub( add( mul(vx,(u+(sx::float+random()*jitter)/ns::float)/nx::float - 0.5),
               mul(vy,0.5 - (v+(sy::float+random()*jitter)/ns::float)/ny::float)
          ), vz) 
        )) as sample
        from params, 
          generate_series(0,(select ns from params)-1) sx,
          generate_series(0,(select ns from params)-1) sy
      ) samples
    ) as pixel
    from view
  )
-- PPM format (comment out first two lines if exporting directly from pgadmin)
select 'P3'
union all 
select nx::text || ' ' || ny::text as "P3" from params
union all select '255'
union all select color(pixel) from pixels
