#!/bin/bash

#VARIAVEIS NAGIOS
NAGIOS_OK=0
NAGIOS_WARNING=1
NAGIOS_CRITICAL=2
NAGIOS_UNKNOWN=3

PROGNAME=`basename $0 .sh`
VERSION="Version 0.02"

WGET=/usr/bin/wget
GREP=/bin/grep
NC=/bin/nc


print_version() {
    echo "$VERSION"
}

print_help() {
    print_version $PROGNAME $VERSION
    echo ""
    echo "$PROGNAME is a Nagios plugin to check a specific Firebird Servers."
    echo ""
    echo "$PROGNAME -u user -p password -H host -a action"
    echo ""
    echo "Options:"
    echo "  -H/--host)"
    echo "      Host Name of the server"
    echo "  -u/--user)"
    echo "      User name for authentication on Tomcat Manager Application"
    echo "  -p/--password)"
    echo "      Password for authentication on Tomcat Manager Application"
    echo "  -d/--database)"
    echo "      Database"
    echo "  -a/--action)"
    echo "      Actions (connection, timesync, custom_query)"
    echo "          connection - Test connection"
    echo "          timesync - Verifies the connection between the server and the database"
    echo "          custom_query - Customized query. Required --query option"
    echo "  -q/--query)"
    echo "      SQL query returning a specified by --valype value"
    echo "  -v/--valtype)"
    echo "      Specifies the value returned"
    echo "          seconds - expects a value in seconds"
    echo "              -w/--warning and -c/--critical necessary."
    echo "          days - expects a value in days"
    echo "              -w/--warning and -c/--critical necessary."
    echo "          integer - expects a value integer"
    echo "              -w/--warning and -c/--critical necessary."
    echo "          string - under construction"
    echo "              -e/--expected) Expect string"
    exit $ST_UK
}

if [ ! -x "$WGET" ]; then echo -e "wget not found.\nsudo apt-get install wget"; exit $NAGIOS_CRITICAL; fi
if [ ! -x "$GREP" ]; then echo -e "grep not found.\nsudo apt-get install grep"; exit $NAGIOS_CRITICAL; fi
if [ ! -x "$NC" ]; then echo -e "nc not found.\nsudo apt-get install nc"; exit $NAGIOS_CRITICAL; fi

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
        --valtype|-v)
            VALTYPE="$2"
            shift
            ;;
        --expected|-e)
            EXPECTED_STRING="$2"
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
function verifyquery { if [ -z "$CUSTOM_QUERY" ]; then echo "Necessary --query parameter."; exit $NAGIOS_UNKNOWN; fi }
function parameterexpected { if [ -z $EXPECTED_STRING ]; then echo "Necessary --expected parameter."; exit $NAGIOS_UNKNOWN; fi }

function check_connection { 
if [ `nc -z $HOST 3050 < /dev/null; echo $?` != 0 ]; then
    echo "FIREBIRD_CONNECTION UNKNOWN: DB \"$DATABASE\" (host:$HOST) error.";
    exit $NAGIOS_UNKNOWN;
fi
}

function check_parameters {
    parametersnull;
    parametersincorrets;
}

# VALIDACAO DO RETORNO
function validate_valtype() {
value=$1
case "$VALTYPE" in
    integer)
        if [ -n "$(echo $value | sed 's/[+-]*[0-9][0-9]*//')" ] ; then
            echo 0;
        else

            echo 1;
        fi
        ;;
    string)
        echo 1;
        ;;
    seconds)
        if [ -n "$(echo $value | sed 's/[+-]*[0-9][0-9]*//')" ] ; then
            echo 0;
        else
            echo 1;
        fi
        ;;
    days|day)
        if [ -n "$(echo $value | sed 's/[+-]*[0-9][0-9]*//')" ] ; then
            echo 0;
        else
            echo 1;
        fi
        ;;
    *)
        echo 0;
        exit $NAGIOS_UNKNOWN
        ;;
esac
}


function connection {

check_connection;

FB_RESULT_CONNECTION=`isql-fb -user $USER -password $PASSWORD $HOST:$DATABASE << "EOF"
SHOW DATABASE;
EOF
`
RETVAL=$?
if [ $RETVAL -eq 1 ]; then
        echo "FIREBIRD_CONNECTION CRITICAL: DB \"$DATABASE\" (host:$HOST) error."
        exit $NAGIOS_CRITICAL
fi

echo "FIREBIRD_CONNECTION OK: DB \"$DATABASE\" (host:$HOST) successfully established."
exit $NAGIOS_OK
}

function timesync {
#Compare database time to local system time

check_parameters;
check_connection;

FB_RESULT_DATAHORA=`isql-fb -user $USER -password $PASSWORD $HOST:$DATABASE << "EOF"
select current_timestamp from RDB\$DATABASE;;
EOF
`
RETVAL=$?
if [ $RETVAL -eq 1 ]; then
        echo "FIREBIRD_TIMESYNC CRITICAL: Database: \"$DATABASE\" (host:$HOST) error connection."
        exit $NAGIOS_CRITICAL
fi

    HORA_SERVIDOR=`date +"%Y-%m-%d %H:%M:%S.%s"`
    HORA_FIREBIRD=`echo $FB_RESULT_DATAHORA | cut -d " " -f 3-`
    HORA_FIREBIRD_TIMESTAMP=`date +%s -d "$HORA_FIREBIRD"`
    HORA_SERVIDOR_TIMESTAMP=`date +%s -d "$HORA_SERVIDOR"`

    DATEDIFF=$(($HORA_SERVIDOR_TIMESTAMP-$HORA_FIREBIRD_TIMESTAMP))
    MINUTES=$(($DATEDIFF/60))

    if [ $DATEDIFF -gt $CRITICAL ]; then
        echo "FIREBIRD_TIMESYNC CRITICAL: Database: \"$DATABASE\" (host:$HOST) timediff=$DATEDIFF DB=$HORA_FIREBIRD Local=$HORA_SERVIDOR"
        exit $NAGIOS_CRITICAL
    elif [ $DATEDIFF -gt $WARNING ]; then
        echo "FIREBIRD_TIMESYNC WARNING: Database: \"$DATABASE\" (host:$HOST) timediff=$DATEDIFF DB=$HORA_FIREBIRD Local=$HORA_SERVIDOR"
        exit $NAGIOS_WARNING
    else
	echo "FIREBIRD_TIMESYNC OK: Database: \"$DATABASE\" (host:$HOST) timediff=$DATEDIFF DB=$HORA_FIREBIRD Local=$HORA_SERVIDOR"
        exit $NAGIOS_OK
    fi

}

function custom_query {
check_connection;

verifyquery;

FB_RESULT_QUERY=`echo "set list; $CUSTOM_QUERY;" | isql-fb -user $USER -password $PASSWORD $HOST:$DATABASE`

if [ $VALTYPE == "seconds" -o $VALTYPE == "day" -o $VALTYPE == "integer" ]; then
    check_parameters;
    FB_RESULT_FINAL=`echo $FB_RESULT_QUERY | sed -e 's/[a-zA-Z\ \_\-]//g'`
    VALIDATE_RETURN=`validate_valtype $FB_RESULT_FINAL`

    if [ $VALIDATE_RETURN -eq 0 ]; then echo "FIREBIRD_CUSTOM_QUERY UNKNOWN: Database: \"$DATABASE\" (host: \"$HOST\") String or type of argument returned is not valid!"; exit $NAGIOS_UNKNOWN; fi

    if [ $FB_RESULT_FINAL -ge $CRITICAL ]; then
        echo "FIREBIRD_CUSTOM_QUERY CRITICAL: Database: \"$DATABASE\" (host: \"$HOST\") $FB_RESULT_FINAL";
        exit $NAGIOS_CRITICAL;
    elif [ $FB_RESULT_FINAL -ge $WARNING ]; then
        echo "FIREBIRD_CUSTOM_QUERY WARNING: Database: \"$DATABASE\" (host: \"$HOST\") $FB_RESULT_FINAL";
        exit $NAGIOS_WARNING;
    else
        echo "FIREBIRD_CUSTOM_QUERY OK: Database: \"$DATABASE\" (host: \"$HOST\") $FB_RESULT_FINAL";
        exit $NAGIOS_OK;
    fi
elif [ $VALTYPE == "string" ]; then
    if [ `echo $FB_RESULT_QUERY | grep $EXPECTED_STRING | wc -l` -gt 0 ]; then
        echo "FIREBIRD_CUSTOM_QUERY OK: Database: \"$DATABASE\" (host: \"$HOST\") String $EXPECTED_STRING found.";
    else
        echo "FIREBIRD_CUSTOM_QUERY CRITICAL: Database: \"$DATABASE\" (host: \"$HOST\") $EXPECTED_STRING not found.";        
    fi
fi
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
