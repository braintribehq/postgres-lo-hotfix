#!/bin/bash

if [ -z ${1} ] || [ "${1}" == "-?" ] || [ "${1}" == "--help" ]; then
	echo 'Cleans up large objects in Postgres'
	echo
	echo "Usage: ${0} -h hostname -p port -U user -W password -d database"
	echo
  echo '  -h'
	echo '                  DB hostname to connect to.'
  echo '  -p'
	echo '                  DB port to connect to, usually 5432.'
	echo '  -U'
	echo '                  Username to use for DB connection'
	echo '  -W'
	echo '                  Password for DB connection'
  echo '  -d'
	echo '                  DB name'
  echo '  -n'
	echo '                  Dry run. List number of object we are going to delete'
	echo '  -?, --help'
	echo '                  Displays this help. This cannot be combined with any other option.'
	echo
	exit 0
fi

database=""
hostname=""
username=""
pass=""
port=""

while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-h)
			hostname="$2"
			shift # past argument
			shift # past value
			;;
		-p)
			port="$2"
			shift # past argument
			shift # past value
			;;
		-U)
			username="$2"
			shift # past argument
			shift # past value
			;;
		-W)
			pass="$2"
			shift # past argument
			shift # past value
			;;
		-d)
			database="$2"
			shift # past argument
			shift # past value
			;;
		*) # when there is no flag
			echo "Unsupported argument: ${1}"
			exit 1
			;;
	esac
done

echo "Configuration: host:" $hostname ", port:" $port:", user:" $username ", password:" $pass ", database:" $database

# fill table with ids of all large objects
echo "Creating table to store oids"
cat << EOF | PGPASSWORD=$pass psql -U $username -h $hostname -p $port $database
DROP TABLE IF EXISTS vacuum_lobj;
CREATE TABLE vacuum_lobj AS 
SELECT oid AS lo FROM pg_largeobject_metadata;
CREATE INDEX ON vacuum_lobj(lo);
EOF

#print count of objects to delete
countallobj=$(echo 'SELECT count(*) as count FROM vacuum_lobj' | PGPASSWORD=$pass psql -Aqt -U $username -h $hostname -p $port $database)
echo "All objects found: $countallobj"

#delete used objects refs from table
echo "Deleting referenced objects from oid table"
cat << EOF |  PGPASSWORD=$pass psql -At -U $username -h $hostname -p $port $database | awk -F '|' '{print "DELETE FROM vacuum_lobj WHERE lo IN (SELECT " $3 "::oid FROM " $1 ".\"" $2 "\");"}' | PGPASSWORD=$pass psql -ebAt -U $username -h $hostname -p $port $database

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
echo "Objects to be removed: $count"

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
for (( i=1; i<=$maxcount; i++ )) 
do
  echo "loop $i of $maxcount"
  echo 'SELECT unlink_orphan_los()' | PGPASSWORD=$pass psql -beqAt -U $username -h $hostname -p $port $database
done  

#cleanup
cat << EOF | PGPASSWORD=$pass psql -U $username -h $hostname -p $port $database
DROP TABLE IF EXISTS vacuum_lobj;
DROP FUNCTION IF EXISTS unlink_orphan_los ( ) ;
VACUUM ANALYZE VERBOSE pg_largeobject;
VACUUM ANALYZE VERBOSE pg_largeobject_metadata;
EOF
