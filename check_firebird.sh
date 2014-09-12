#!/bin/bash

#VARIAVEIS NAGIOS
NAGIOS_OK=0
NAGIOS_WARNING=1
NAGIOS_CRITICAL=2
NAGIOS_UNKNOWN=3

PROGNAME=`basename $0 .sh`
VERSION="Version 0.01"

WGET=/usr/bin/wget
GREP=/bin/grep

print_version() {
    echo "$VERSION"
}

print_help() {
    print_version $PROGNAME $VERSION
    echo ""
    echo "$PROGNAME is a Nagios plugin to check a specific Firebird Servers."
    echo ""
    echo "$PROGNAME -u user -p password -H host -P port -a action"
    echo ""
    echo "Options:"
    echo "  -H/--host)"
    echo "     Host Name of the server"
    echo "  -u/--user)"
    echo "     User name for authentication on Tomcat Manager Application"
    echo "  -p/--password)"
    echo "     Password for authentication on Tomcat Manager Application"
    echo "  -a/--action)"
    echo "     Actions (connection)"
    echo "  -d/--database)"
    echo "     Database"
    exit $ST_UK
}

if [ ! -x "$WGET" ]
then
	echo "wget not found!"
	exit $NAGIOS_CRITICAL
fi

if [ ! -x "$GREP" ]
then
	echo "grep not found!"
	exit $NAGIOS_CRITICAL
fi

if test -z "$1"
then
	print_help
	exit $NAGIOS_CRITICAL
fi

while test -n "$1"; do
    case "$1" in
        --help|-h)
            print_help
            exit $ST_UK
            ;;
        --version|-v)
            print_version $PROGNAME $VERSION
            exit $ST_UK
            ;;
        --user|-u)
            USER=$2
            shift
            ;;
        --password|-p)
            PASSWORD=$2
            shift
            ;;
        --host|-H)
            HOST=$2
            shift
            ;;
        --database|-d)
            DATABASE=$2
            shift
            ;;
        --warning|-w)
            WARNING=$2
            shift
            ;;
        --critical|-c)
            CRITICAL=$2
            shift
            ;;
        --action|-a)
            ACTION=$2
            shift
            ;;
        --query|-q)
            set -f
            CUSTOM_QUERY="$2"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            print_help
            exit $ST_UK
            ;;
        esac
    shift
done

if [ -z $ACTION ]; then
    echo "Necessary to inform the desired action."
    exit $NAGIOS_UNKNOWN
fi

function parametersnull { if [ -z $WARNING ] || [ -z $CRITICAL ]; then echo "Parameters of WARNING and CRITICAL are needed."; exit $NAGIOS_UNKNOWN; fi }
function parametersincorrets { if [ $WARNING -ge $CRITICAL ]; then echo "WARNING must be less than CRITICAL."; exit $NAGIOS_UNKNOWN; fi }
function verifyquery { if [ -z $CUSTOM_QUERY ]; then echo "Necessary --query parameter."; exit $NAGIOS_UNKNOWN; fi }

function check_parameters {
    parametersnull;
    parametersincorrets;
}

function connection {

FB_RESULT_CONNECTION=`isql-fb -user $USER -password $PASSWORD $HOST:$DATABASE << "EOF"
SHOW DATABASE;
EOF
`
RETVAL=$?
if [ $RETVAL -eq 1 ]; then
        echo "Nao foi possivel conexao com a base de dados $HOST:$DATABASE"
        exit $NAGIOS_CRITICAL
fi

echo "OK: Connection to the database successfully established."
exit $NAGIOS_OK
}

function timesync {
#Compare database time to local system time

check_parameters;

FB_RESULT_DATAHORA=`isql-fb -user $USER -password $PASSWORD $HOST:$DATABASE << "EOF"
select current_timestamp from RDB\$DATABASE;;
EOF
`
RETVAL=$?
if [ $RETVAL -eq 1 ]; then
        echo "Nao foi possivel conexao com a base de dados $HOST:$DATABASE"
        exit $NAGIOS_CRITICAL
fi

HORA_SERVIDOR=`date +"%Y-%m-%d %H:%M:%S.%s"`
HORA_FIREBIRD=`echo $FB_RESULT_DATAHORA | cut -d " " -f 3-`
HORA_FIREBIRD_TIMESTAMP=`date +%s -d "$HORA_FIREBIRD"`
HORA_SERVIDOR_TIMESTAMP=`date +%s -d "$HORA_SERVIDOR"`

DATEDIFF=$(($HORA_SERVIDOR_TIMESTAMP-$HORA_FIREBIRD_TIMESTAMP))
MINUTES=$(($DATEDIFF/60))

    if [ $DATEDIFF -gt $CRITICAL ]; then
        echo "CRITICAL: $DATEDIFF seconds"
        exit $NAGIOS_CRITICAL
    elif [ $DATEDIFF -gt $WARNING ]; then
        echo "WARNING: $DATEDIFF seconds"
        exit $NAGIOS_WARNING
    else
        echo "OK: $DATEDIFF seconds"
        exit $NAGIOS_OK
    fi
}

function custom_query {
# Custom query in FirebirdSQL
# 1 - connect
# 2 - Execute the function
# 3 - Show the result (with formating) 
check_parameters;
verifyquery;

FB_RESULT_QUERY=`echo "set list ;  $CUSTOM_QUERY;" | isql-fb -user $USER -password $PASSWORD $HOST:$DATABASE`
FB_RESULT_FINAL=`echo $FB_RESULT_QUERY | sed -e 's/[a-zA-Z\ ]//g'`

echo "O meu resultado final é $FB_RESULT_FINAL"

}

case "$ACTION" in
    connection)
        connection
        ;;
    timesync)
        timesync
        ;;
    custom_query)
        custom_query
        ;;
    *)
        echo "Unknown argument: $1"
        print_help
        exit $ST_UK
        ;;
    esac
shift    

exit 0
