#!/bin/bash

database="conversion"
hostname="localhost"
username="postgres"
pass="postgres"
port="5432"

# fill table with ids of all large objects
cat << EOF | PGPASSWORD=$pass psql -U $username -h $hostname -p $port $database

DROP TABLE IF EXISTS vacuum_lobj;
CREATE TABLE vacuum_lobj AS 
SELECT oid AS lo FROM pg_largeobject_metadata;
CREATE INDEX ON vacuum_lobj(lo);
EOF

#delete used objects refs from table
cat << EOF |  PGPASSWORD=$pass psql -At -U $username -h $hostname -p $port $database | awk -F '|' '{print "DELETE FROM vacuum_lobj WHERE lo IN (SELECT " $3 "::oid FROM " $1 ".\"" $2 "\");"}' | PGPASSWORD=$pass psql -ebqAt -U $username -h $hostname -p $port $database

SELECT s.nspname, c.relname, a.attname
FROM pg_class c, pg_attribute a, pg_namespace s, pg_type t
WHERE a.attnum > 0 AND NOT a.attisdropped
AND a.attrelid = c.oid 
AND a.atttypid = t.oid 
AND c.relnamespace = s.oid
AND t.typname in ('oid', 'lo','text')
AND c.relkind in ('r', 'v')
AND s.nspname !~ '^pg_' 
AND c.relname !~ 'vacuum_lobj';
EOF

#print count of objects to delete
count=$(echo 'SELECT count(*) as count FROM vacuum_lobj' | PGPASSWORD=$pass psql -Aqt -U $username -h $hostname -p $port $database)
echo "Objects found: $count"

#declare function
cat << EOF | PGPASSWORD=$pass psql -At -U $username -h $hostname -p $port $database
CREATE OR REPLACE FUNCTION unlink_orphan_los() RETURNS VOID AS \$\$
DECLARE
  iterator integer := 0;
  largeoid OID;
  myportal CURSOR FOR SELECT lo FROM vacuum_lobj;
BEGIN
  OPEN myportal;
  LOOP
    FETCH myportal INTO largeoid;
    EXIT WHEN NOT FOUND;
    PERFORM lo_unlink(largeoid);
    DELETE FROM vacuum_lobj WHERE lo = largeoid;
    iterator := iterator + 1;
    RAISE NOTICE '(%) removed lo %', iterator, largeoid;
    IF iterator = 300 THEN EXIT; END IF;
  END LOOP;
END;\$\$LANGUAGE plpgsql;
EOF

#unlink objects in a loop
maxcount=$(( $count / 300 + 1 ))
echo "maxcount: $maxcount"
for (( i=1; i<=$maxcount; i++ )) 
do
  echo "loop $i of $maxcount"
  echo 'SELECT unlink_orphan_los()' | PGPASSWORD=$pass psql -beqAt -U $username -h $hostname -p $port $database
done  

#cleanup
cat << EOF | PGPASSWORD=$pass psql -U $username -h $hostname -p $port $database
DROP TABLE IF EXISTS vacuum_lobj;
DROP FUNCTION IF EXISTS unlink_orphan_los ( ) ;
--VACUUM ANALYZE VERBOSE pg_largeobject;
--VACUUM ANALYZE VERBOSE pg_largeobject_metadata;
EOF
