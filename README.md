# About this tool
Usually, when dealing with lots of LOBs in PostgreSQL databases, a combination of the
[vacuumlo](https://www.postgresql.org/docs/9.1/vacuumlo.html) tool and [VACUUM FULL](https://www.postgresql.org/docs/9.1/sql-vacuum.html) SQL commands is used to reclaim storage on the database layer. This is neccessary since Postgres does not remove references to LOBs when removing related database rows (leaving behind orphaned LOBs in table `pg_largeobjects`). Unfortunately, the official tooling does not handle CLOBs in a safe manner, and running `vacuumlo` lead to broken LOB references. This is a custom "vacuumlo" replacement that handles CLOB references correctly.

#### Available options
​
```bash
> cleanup-adx.sh --help
Cleans up large objects in Postgres
​
Usage: cleanup-adx.sh -h hostname -p port -U user -W password -d database
​
  -h
                  DB hostname to connect to.
  -p
                  DB port to connect to, usually 5432.
  -U
                  Username to use for DB connection
  -W
                  Password for DB connection
  -d
                  DB name
  -?, --help
                  Displays this help. This cannot be combined with any other option.
```

#### Example usage
​
The following command will start the script and remove orphaned LOBs on the given DB:
​
```bash
./cleanup-adx.sh -h database.host.name \
    -p 5432 \
    -U database_user \
    -W 'secretpassword' \
    -d database_name
```

#### VACUUM FULL Considerations
The final step in reclaiming storage is to do a `VACUUM FULL` run. This, however, requires a lock on the tables that are considered by the `VACCUM FULL` execution, so it is neccessary to shutdown all operations on DB while `VACUUM FULL` is running. Please also make sure that there is enough free disk space available, at least the size of the largest table in the database should be free. This step is only needed after

Here is an example of how to invoke `VACUUM FULL`:

```sql
> psql -c"vacuum full verbose analyze" -e \
    -h database.host.name \
    -U database_user database_name
```

# Usage guidelines
PostgreSQL database will perform regular cleanup using VACUUM run by [autovacuum daemon](https://www.postgresql.org/docs/9.6/routine-vacuuming.html#AUTOVACUUM). This however won't affect large objects. It is recommended to run cleanup-adx script regularly (e.g. once every week/day depending on DB load). No other action is required unless a large amount of data was deleted by the script. Only after removing a large amount of data please also run VACUUM FULL to reclaim lost disk space.

# Related PostgreSQL Documentation
* description of VACUUM command https://www.postgresql.org/docs/9.6/sql-vacuum.html
* vacuuming best practices https://www.postgresql.org/docs/9.6/routine-vacuuming.html
* get size of database objects https://wiki.postgresql.org/wiki/Disk_Usage
