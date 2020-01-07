# geocoder-loader

An alternative way of adding TIGER data to a Postgres database for PostGIS geocoding.

This follows the same rules as the `Loader_Generate_Script` function, but runs somewhat more robustly and adds cleaning tasks for corrupted downloads.

### Install

Create the geocoder extension in your Postgres db:
```sql
CREATE EXTENSION postgis_tiger_geocoder CASCADE;
CREATE EXTENSION address_standardizer CASCADE;
```

To specify your database connection, use the [`PG` environment variables](https://www.postgresql.org/docs/current/libpq-envars.html) (e.g. `export PGUSER=postgres PGDATABASE=postgres`)  

Then add the national files:
```bash
make nation
```

### Usage

Working with a single state:

```bash
# Download data for a state and load into database
make STATEFIPS=36
```

```bash
# Remove downloaded and loaded data for a state
make STATEFIPS=36 clean
```

```bash
# Download data for a state
make STATEFIPS=36 download
```

To download then load data for all states (and territories), use `xargs` or [GNU `parallel`](https://www.gnu.org/software/parallel/):
```bash
cut -f 1 config/stateabbrev.txt | xargs -I {} make download STATEFIPS={}
cut -f 1 config/stateabbrev.txt | xargs -I {} make default STATEFIPS={}
```