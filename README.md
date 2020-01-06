# geocoder-loader

An alternative way of adding TIGER data to a Postgres database for PostGIS geocoding.

This follows the same rules as the `Loader_Generate_Script` function, but runs somewhat more robustly and adds cleaning tasks for corrupted downloads.

### Install

Create the geocoder extension in your Postgres db:
```sql
CREATE EXTENSION postgis_tiger_geocoder CASCADE:
```

### Usage

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
