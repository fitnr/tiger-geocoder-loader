SHELL = bash

unzip = unzip
wget = wget
psql = psql
s2pgflags = -D -s 4269 -g the_geom -W latin1
s2pg = shp2pgsql $(s2pgflags)
temp = temp

STATEFIPS = 41
YEAR = 2017

include config/counties-$(YEAR).ini

sa := $(shell grep $(STATEFIPS) config/stateabbrev.txt | cut -f 2)
countyfips := $(addprefix $(STATEFIPS),$(counties_$(STATEFIPS)))

base = www2.census.gov/geo/tiger/TIGER$(YEAR)

place = PLACE/tl_$(YEAR)_$(STATEFIPS)_place
cousub = COUSUB/tl_$(YEAR)_$(STATEFIPS)_cousub
tract = TRACT/tl_$(YEAR)_$(STATEFIPS)_tract
addr = $(foreach f,$(countyfips),ADDR/tl_$(YEAR)_$f_addr)
faces = $(foreach f,$(countyfips),FACES/tl_$(YEAR)_$f_faces)
edges = $(foreach f,$(countyfips),EDGES/tl_$(YEAR)_$f_edges)
featnames = $(foreach f,$(countyfips),FEATNAMES/tl_$(YEAR)_$f_featnames)
state = STATE/tl_$(YEAR)_us_state
county = COUNTY/tl_$(YEAR)_us_county
shps = $(cousub) $(place) $(tract) $(addr) $(faces) $(edges) $(state) $(county)
dbfs = $(featnames)
files = $(shps) $(dbfs)

tables = tract cousub place faces featnames edges addr

.PHONY: default $(tables) post-% load-% preload-% stage clean clean-% download

default: post-place post-faces post-featnames post-edges post-addr

$(tables): %: post-%

post-cousub: load-cousub

post-place: load-place
	$(psql) -c "CREATE INDEX idx_$(sa)_place_soundex_name ON tiger_data.$(sa)_place USING btree (soundex(name));"
	$(psql) -c "CREATE INDEX tiger_data_$(sa)_place_the_geom_gist ON tiger_data.$(sa)_place USING gist(the_geom);"
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_place ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"

post-faces: load-faces
	$(psql) -c "CREATE INDEX tiger_data_$(sa)_faces_the_geom_gist ON tiger_data.$(sa)_faces USING gist(the_geom);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_faces_tfid ON tiger_data.$(sa)_faces USING btree (tfid);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_faces_countyfp ON tiger_data.$(sa)_faces USING btree (countyfp);"
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_faces ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "vacuum analyze tiger_data.$(sa)_faces;"

post-featnames: load-featnames
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_featnames_snd_name ON tiger_data.$(sa)_featnames USING btree (soundex(name));"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_featnames_lname ON tiger_data.$(sa)_featnames USING btree (lower(name));"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_featnames_tlid_statefp ON tiger_data.$(sa)_featnames USING btree (tlid,statefp);"
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_featnames ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "vacuum analyze tiger_data.$(sa)_featnames;"

post-edges: load-edges
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_edges ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_edges_tlid ON tiger_data.$(sa)_edges USING btree (tlid);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_edgestfidr ON tiger_data.$(sa)_edges USING btree (tfidr);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_edges_tfidl ON tiger_data.$(sa)_edges USING btree (tfidl);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_edges_countyfp ON tiger_data.$(sa)_edges USING btree (countyfp);"
	$(psql) -c "CREATE INDEX tiger_data_$(sa)_edges_the_geom_gist ON tiger_data.$(sa)_edges USING gist(the_geom);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_edges_zipl ON tiger_data.$(sa)_edges USING btree (zipl);"
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_zip_state_loc(CONSTRAINT pk_$(sa)_zip_state_loc PRIMARY KEY(zip,stusps,place)) INHERITS(tiger.zip_state_loc);"
	$(psql) -c "INSERT INTO tiger_data.$(sa)_zip_state_loc(zip,stusps,statefp,place) SELECT DISTINCT e.zipl, '$(sa)', '$(STATEFIPS)', p.name FROM tiger_data.$(sa)_edges AS e INNER JOIN tiger_data.$(sa)_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN tiger_data.$(sa)_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_zip_state_loc_place ON tiger_data.$(sa)_zip_state_loc USING btree(soundex(place));"
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_zip_state_loc ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "vacuum analyze tiger_data.$(sa)_edges;"
	$(psql) -c "vacuum analyze tiger_data.$(sa)_zip_state_loc;"
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_zip_lookup_base(CONSTRAINT pk_$(sa)_zip_state_loc_city PRIMARY KEY(zip,state, county, city, statefp)) INHERITS(tiger.zip_lookup_base);"
	$(psql) -c "INSERT INTO tiger_data.$(sa)_zip_lookup_base(zip,state,county,city, statefp) SELECT DISTINCT e.zipl, '$(sa)', c.name,p.name,'$(STATEFIPS)' FROM tiger_data.$(sa)_edges AS e INNER JOIN tiger.county As c  ON (e.countyfp = c.countyfp AND e.statefp = c.statefp AND e.statefp = '$(STATEFIPS)') INNER JOIN tiger_data.$(sa)_faces AS f ON (e.tfidl = f.tfid OR e.tfidr = f.tfid) INNER JOIN tiger_data.$(sa)_place As p ON(f.statefp = p.statefp AND f.placefp = p.placefp ) WHERE e.zipl IS NOT NULL;"
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_zip_lookup_base ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_zip_lookup_base_citysnd ON tiger_data.$(sa)_zip_lookup_base USING btree(soundex(city));"

post-addr: load-addr
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_addr ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_addr_least_address ON tiger_data.$(sa)_addr USING btree (least_hn(fromhn,tohn) );"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_addr_tlid_statefp ON tiger_data.$(sa)_addr USING btree (tlid, statefp);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_addr_zip ON tiger_data.$(sa)_addr USING btree (zip);"
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_zip_state(CONSTRAINT pk_$(sa)_zip_state PRIMARY KEY(zip,stusps)) INHERITS(tiger.zip_state); "
	$(psql) -c "INSERT INTO tiger_data.$(sa)_zip_state(zip,stusps,statefp) SELECT DISTINCT zip, '$(sa)', '$(STATEFIPS)' FROM tiger_data.$(sa)_addr WHERE zip is not null;"
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_zip_state ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "vacuum analyze tiger_data.$(sa)_addr;"

post-tract: load-tract

load-place: $(temp)/$(place).shp | stage
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_place ( CONSTRAINT pk_$(sa)_place PRIMARY KEY (plcidfp) ) INHERITS (tiger.place);"
	$(s2pg) -c $< tiger_staging.$(sa)_place | $(psql)
	$(psql) -c "ALTER TABLE tiger_staging.$(sa)_place RENAME geoid TO plcidfp; SELECT loader_load_staged_data(lower('$(sa)_place'), lower('$(sa)_place')); ALTER TABLE tiger_data.$(sa)_place ADD CONSTRAINT uidx_$(sa)_place_gid UNIQUE (gid);"

load-cousub: $(temp)/$(cousub).shp | stage
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_cousub (CONSTRAINT pk_$(sa)_cousub PRIMARY KEY (cosbidfp), CONSTRAINT uidx_$(sa)_cousub_gid UNIQUE (gid)) INHERITS(tiger.cousub);"
	$(s2pg) $< tiger_staging.$(sa)_cousub | $(psql)
	$(psql) -c "ALTER TABLE tiger_staging.$(sa)_cousub RENAME geoid TO cosbidfp;SELECT loader_load_staged_data(lower('$(sa)_cousub'), lower('$(sa)_cousub')); ALTER TABLE tiger_data.$(sa)_cousub ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"
	$(psql) -c "CREATE INDEX tiger_data_$(sa)_cousub_the_geom_gist ON tiger_data.$(sa)_cousub USING gist(the_geom);"
	$(psql) -c "CREATE INDEX idx_tiger_data_$(sa)_cousub_countyfp ON tiger_data.$(sa)_cousub USING btree(countyfp);"

load-tract: $(temp)/$(tract).shp | stage
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_tract (CONSTRAINT pk_$(sa)_tract PRIMARY KEY (tract_id) ) INHERITS(tiger.tract); "
	$(s2pg) $< tiger_staging.$(sa)_tract | $(psql)
	$(psql) -c "ALTER TABLE tiger_staging.$(sa)_tract RENAME geoid TO tract_id; SELECT loader_load_staged_data(lower('$(sa)_tract'), lower('$(sa)_tract')); "
	$(psql) -c "CREATE INDEX tiger_data_$(sa)_tract_the_geom_gist ON tiger_data.$(sa)_tract USING gist(the_geom);"
	$(psql) -c "VACUUM ANALYZE tiger_data.$(sa)_tract;"
	$(psql) -c "ALTER TABLE tiger_data.$(sa)_tract ADD CONSTRAINT chk_statefp CHECK (statefp = '$(STATEFIPS)');"

load-addr: $(addprefix load-,$(addr))

load-edges: $(addprefix load-,$(edges))

load-faces: $(addprefix load-,$(faces))

load-featnames: $(addprefix load-,$(featnames))

$(addprefix load-,$(faces)): load-%: $(temp)/%.shp | preload-faces stage
	$(s2pg) $< tiger_staging.$(sa)_faces | $(psql)
	$(psql) -c "SELECT loader_load_staged_data(lower('$(sa)_faces'), lower('$(sa)_faces'));"

$(addprefix load-,$(edges)): load-%: $(temp)/%.shp | preload-edges stage
	$(s2pg) $< tiger_staging.$(sa)_edges | $(psql)
	$(psql) -c "SELECT loader_load_staged_data(lower('$(sa)_edges'), lower('$(sa)_edges'));"

$(addprefix load-,$(featnames)): load-%: $(temp)/%.dbf | preload-featnames stage
	$(s2pg) -n $< tiger_staging.$(sa)_featnames | $(psql)
	$(psql) -c "SELECT loader_load_staged_data(lower('$(sa)_featnames'), lower('$(sa)_featnames'));"

$(addprefix load-,$(addr)): load-%: $(temp)/%.shp | preload-addr stage
	$(s2pg) -n $< tiger_staging.$(sa)_addr | $(psql)
	$(psql) -c "SELECT loader_load_staged_data(lower('$(sa)_addr'), lower('$(sa)_addr'));"

preload-faces: | stage
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_faces ( \
	CONSTRAINT pk_$(sa)_faces PRIMARY KEY (gid)) INHERITS (tiger.faces);"

preload-featnames: | stage
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_featnames ( \
	CONSTRAINT pk_$(sa)_featnames PRIMARY KEY (gid)) INHERITS (tiger.featnames); \
	ALTER TABLE tiger_data.$(sa)_featnames ALTER COLUMN statefp SET DEFAULT '$(STATEFIPS)';"

preload-addr: | stage
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_addr \
	( CONSTRAINT pk_$(sa)_addr PRIMARY KEY (gid)) INHERITS (tiger.addr); \
	ALTER TABLE tiger_data.$(sa)_addr ALTER COLUMN statefp SET DEFAULT '$(STATEFIPS)';"

preload-edges: | stage
	$(psql) -c "CREATE TABLE tiger_data.$(sa)_edges( \
	CONSTRAINT pk_$(sa)_edges PRIMARY KEY (gid)) INHERITS (tiger.edges);"

stage:
	$(psql) -c "DROP SCHEMA IF EXISTS tiger_staging CASCADE;"
	$(psql) -c "CREATE SCHEMA tiger_staging;"

load-state: $(temp)/$(state).shp | stage
	$(psql) -c "CREATE TABLE tiger_data.state_all ( \
	CONSTRAINT pk_state_all PRIMARY KEY (statefp), \
	CONSTRAINT uidx_state_all_stusps UNIQUE (stusps), \
	CONSTRAINT uidx_state_all_gid UNIQUE (gid) ) INHERITS(tiger.state)"
	$(s2pg) $< tiger_staging.state | $(psql)
	$(psql) -c "SELECT loader_load_staged_data(lower('state'), lower('state_all')); "
	$(psql) -c "CREATE INDEX tiger_data_state_all_the_geom_gist ON tiger_data.state_all USING gist(the_geom);"
	$(psql) -c "VACUUM ANALYZE tiger_data.state_all"

load-county: $(temp)/$(county).shp | stage
	$(psql) -c "CREATE TABLE tiger_data.county_all( \
	CONSTRAINT pk_tiger_data_county_all PRIMARY KEY (cntyidfp), \
	CONSTRAINT uidx_tiger_data_county_all_gid UNIQUE (gid)) INHERITS(tiger.county)" 
	$(s2pg) $< tiger_staging.county | $(psql)
	$(psql) -c "ALTER TABLE tiger_staging.county RENAME geoid TO cntyidfp; SELECT loader_load_staged_data(lower('county'), lower('county_all'));"
	$(psql) -c "CREATE INDEX tiger_data_county_the_geom_gist ON tiger_data.county_all USING gist(the_geom);"
	$(psql) -c "CREATE UNIQUE INDEX uidx_tiger_data_county_all_statefp_countyfp ON tiger_data.county_all USING btree(statefp, countyfp);"
	$(psql) -c "CREATE TABLE tiger_data.county_all_lookup(CONSTRAINT pk_county_all_lookup PRIMARY KEY (st_code, co_code)) INHERITS (tiger.county_lookup);"
	$(psql) -c "VACUUM ANALYZE tiger_data.county_all;"
	$(psql) -c "INSERT INTO tiger_data.county_all_lookup(st_code, state, co_code, name) \
	SELECT statefp::integer, s.abbrev, c.countyfp::integer, c.name FROM tiger_data.county_all as c INNER JOIN state_lookup as s USING (statefp)"
	$(psql) -c "VACUUM ANALYZE tiger_data.county_all_lookup;" 

download: $(foreach z,$(files),$(base)/$z.zip) \
	$(foreach z,$(shps),$(temp)/$z.shp) \
	$(foreach z,$(dbfs),$(temp)/$z.dbf)

$(foreach z,$(files),$(temp)/$z.dbf): $(temp)/%.dbf: $(base)/%.zip | $(temp)
	@mkdir -p $(@D)
	$(unzip) -q -o -d $(@D) $<
	@touch $@

$(foreach z,$(files),$(temp)/$z.shp): $(temp)/%.shp: $(base)/%.zip | $(temp)
	@mkdir -p $(@D)
	$(unzip) -q -o -d $(@D) $<
	@touch $@

$(foreach z,$(files),$(base)/$z.zip): $(base)/%.zip:
	$(wget) -q -t 5 --mirror --reject=html https://$@

$(temp): ; mkdir -p $(temp)

clean: $(addprefix clean-,$(tables))

clean-%: ; $(psql) -c "drop table if exists tiger_data.$(sa)_$*"
