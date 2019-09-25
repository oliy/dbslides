PG_HOST?=localhost
PG_USER?=postgres
PG_DB?=test
PSQL:=psql -h $(PG_HOST) $(PG_DB) $(PG_USER) -Ppager=off 

GRAPH_DEPS=sql/graph_deps.sql
define GRAPH_DEPS_START
-- This file was generated from this project's package structure.
-- See Makefile for re/generation
drop table if exists dep_list;
create table dep_list (
  id serial primary key,
  parent text not null,
  child text not null
);
insert into dep_list(parent, child) values 
endef
export GRAPH_DEPS_START

help:
	@echo "SQL Tips and Tricks project"
	@echo ""
	@echo "To show slides:          make slides"
	@echo "To start db container:   make db"
	@echo "To run examples: (assumes db started)"
	@echo "    Raytracer            make ray"
	@echo ""
	@echo "Current DB settings:"
	@echo "    PG_HOST:   $(PG_HOST)"
	@echo "    PG_USER:   $(PG_USER)"
	@echo "    PG_DB:     $(PG_DB)"
	@echo "    DB status: "`$(PSQL) -Atc "select 'ok';" || echo "failed"`

node_modules:
	yarn

db:
	docker-compose up -d db
	sleep 5
	-psql -h $(PG_HOST) "postgres" "postgres" -c "create database test;" 

slides: node_modules
	yarn start

pivot:
	$(PSQL) -f sql/pivot.sql -e

pivot_agg:
	$(PSQL) -f sql/pivot_agg.sql -e

tags:
	$(PSQL) -f sql/tags.sql -e

tree:
	$(PSQL) -f sql/tree.sql -e

sudoku:
	$(PSQL) -f sql/sudoku.sql -e

ray:
	$(PSQL) -f sql/ray.sql -qAt | grep -v '^$$' > img/tmp.ppm
	open img/tmp.ppm

$(GRAPH_DEPS): yarn.lock
	echo "$$GRAPH_DEPS_START" > $(GRAPH_DEPS)
	cat package.json  | jq -cr '.devDependencies | keys[] | "('"'"'dbslides'"'"','"'"'\(.)'"'"'),"' >> $(GRAPH_DEPS)
	yarn list --json | jq -cr '..|select(.name?)|{parent:(.name|gsub("@.*";"")),child:((.children//[])[].name|gsub("@.*";""))}|"('"'"'\(.parent)'"'"','"'"'\(.child)'"'"'),"' >> $(GRAPH_DEPS)
	echo "('','');" >> $(GRAPH_DEPS)
	# remove extraneous end marker
	echo "delete from dep_list where parent='' and child='';" >> $(GRAPH_DEPS)
	# break stupid circular dependency
	echo "delete from dep_list where parent='global-modules' and child='resolve-dir';" >> $(GRAPH_DEPS)

graph: $(GRAPH_DEPS)
	$(PSQL) -f $(GRAPH_DEPS)
	$(PSQL) -f sql/graph.sql
