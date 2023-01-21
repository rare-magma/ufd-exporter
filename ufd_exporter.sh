#!/usr/bin/env bash

set -Eeo pipefail

dependencies=(awk curl date gzip jq tr)
for program in "${dependencies[@]}"; do
    command -v "$program" >/dev/null 2>&1 || {
        echo >&2 "Couldn't find dependency: $program. Aborting."
        exit 1
    }
done

# shellcheck source=/dev/null
source "$CREDENTIALS_DIRECTORY/creds"

[[ -z "${INFLUXDB_HOST}" ]] && echo >&2 "INFLUXDB_HOST is empty. Aborting" && exit 1
[[ -z "${INFLUXDB_API_TOKEN}" ]] && echo >&2 "INFLUXDB_API_TOKEN is empty. Aborting" && exit 1
[[ -z "${ORG}" ]] && echo >&2 "ORG is empty. Aborting" && exit 1
[[ -z "${BUCKET}" ]] && echo >&2 "BUCKET is empty. Aborting" && exit 1
[[ -z "${UFD_USERNAME}" ]] && echo >&2 "UFD_USERNAME is empty. Aborting" && exit 1
[[ -z "${UFD_PASSWORD}" ]] && echo >&2 "UFD_PASSWORD is empty. Aborting" && exit 1
[[ -z "${CUPS}" ]] && echo >&2 "CUPS is empty. Aborting" && exit 1

AWK=$(command -v awk)
CURL=$(command -v curl)
DATE=$(command -v date)
GZIP=$(command -v gzip)
JQ=$(command -v jq)
TR=$(command -v tr)

TODAY=$($DATE +"%d/%m/%Y")
WEEK_AGO=$($DATE +"%d/%m/%Y" --date "2 weeks ago")

INFLUXDB_URL="https://$INFLUXDB_HOST/api/v2/write?precision=s&org=$ORG&bucket=$BUCKET"
UFD_LOGIN_URL="https://api.ufd.es/ufd/v1.0/login"
UFD_API_URL="https://api.ufd.es/ufd/v1.0/consumptions"

ufd_token=$(
    $CURL --silent --compressed \
        --request POST \
        --data "{\"user\": \"$UFD_USERNAME\",\"password\": \"$UFD_PASSWORD\"}" \
        --header 'Accept-Encoding: gzip, deflate, br' \
        --header 'X-Appclientid: ACUFDWeb' \
        --header 'X-AppClient: ACUFDW' \
        --header 'X-Application: ACUFD' \
        --header 'X-Appversion: 1.0.0.0' \
        --header 'X-AppClientSecret: 4CUFDW3b' \
        --header "Content-Type: application/json" \
        --header 'Content-Encoding: application/json' \
        "$UFD_LOGIN_URL" |
        $JQ --raw-output '.accessToken'
)

ufd_query="$UFD_API_URL?filter="
ufd_query+="nif::$UFD_USERNAME"
ufd_query+="%7Ccups::$CUPS%7C"
ufd_query+="startDate::$WEEK_AGO%7C"
ufd_query+="endDate::$TODAY%7C"
ufd_query+="granularity::F%7C"
ufd_query+="unit::K%7C"
ufd_query+="generator::0%7C"
ufd_query+="isDelegate::N%7C"
ufd_query+="measurementSystem::O"

ufd_json=$(
    $CURL --silent --compressed \
        --request GET \
        --header 'Accept-Encoding: gzip, deflate, br' \
        --header "Authorization: Bearer $ufd_token" \
        --header 'X-Appclient: ACUFDW' \
        --header 'X-Appclientsecret: 4CUFDW3b' \
        --header 'X-Application: ACUFD' \
        --header 'X-Appversion: 1.0.0.0' \
        --header "Content-Type: application/json" \
        --header 'Content-Encoding: application/json' \
        "$ufd_query" |
        $JQ '.items'
)

length=$(echo "$ufd_json" | $JQ 'length - 1')

for i in $(seq 0 "$length"); do

    for j in $(seq 0 23); do

        mapfile -t parsed_stats < <(
            echo "$ufd_json" |
                $JQ --raw-output \
                    ".[$i].consumptions.items[$j] | .hour,.consumptionDate,.consumptionValueP1,.consumptionValueP2,.consumptionValueP3,.consumptionValueP4,.consumptionValueP5,.consumptionValueP6" |
                $TR , .
        )

        hour_value=${parsed_stats[0]}

        if [[ $hour_value -eq "null" ]]; then
            break
        fi

        if [[ $hour_value -eq "24" ]]; then
            hour_value="0"
        fi

        if [[ $hour_value -lt "10" ]]; then
            hour_value="0$hour_value"
        fi

        consumptionDate_value=${parsed_stats[1]}

        consumptionValue_P1=${parsed_stats[2]:=0}
        consumptionValue_P2=${parsed_stats[3]:=0}
        consumptionValue_P3=${parsed_stats[4]:=0}
        consumptionValue_P4=${parsed_stats[5]:=0}
        consumptionValue_P5=${parsed_stats[6]:=0}
        consumptionValue_P6=${parsed_stats[7]:=0}

        formatted_date=$(echo "${consumptionDate_value}" | $AWK --field-separator='/' 'OFS="-" {print $3, $2, $1}')
        ts=$($DATE "+%s" --date="$formatted_date ${hour_value}:00:00")

        price_stats+=$(
            printf "\nufd_consumption,hour=%s p1=%s,p2=%s,p3=%s,p4=%s,p5=%s,p6=%s %s" \
                "${formatted_date}T${hour_value}:00:00" "$consumptionValue_P1" "$consumptionValue_P2" \
                "$consumptionValue_P3" "$consumptionValue_P4" "$consumptionValue_P5" "$consumptionValue_P6" "$ts"
        )

    done
done

echo -n "${price_stats:1}" | $GZIP |
    $CURL --silent \
        --request POST "${INFLUXDB_URL}" \
        --header 'Content-Encoding: gzip' \
        --header "Authorization: Token $INFLUXDB_API_TOKEN" \
        --header "Content-Type: text/plain; charset=utf-8" \
        --header "Accept: application/json" \
        --data-binary @-
