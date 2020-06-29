#!/bin/bash

if [[ -z "${1}" && -z "${URL_TO_TEST}" ]]
then
    echo -e "Uso: ${0##*/} [URL]"
    exit 1
elif [[ ! -z "${1}" && -z "${URL_TO_TEST}" ]]
then
    URL_TO_TEST=${1}
fi

########## Configuracion ##########

export TZ="America/Argentina/Buenos_Aires" # Ejemplo: "America/Argentina/Buenos_Aires"

SLACK_API_URL="https://slack.com/api/files.upload" # URL de la API de Slack para enviar archivos
SLACK_API_TOKEN="xoxb-slack-token" # Token xoxb-
SLACK_CHANNEL="#komodin-test" # Canal al que se quiere enviar el mensaje. Tiene que estar agregada la app
SLACK_MESSAGE="Reporte del analisis de GTMetrix para la URL ${URL_TO_TEST} con fecha $(date "+%d/%m/%Y %H:%M") GMT -3" # Mensaje que se va a enviar por Slack

API_EMAIL="test@test.com" # Email del usuario de GTMetrix
API_KEY="00000000000000000000000" # API_KEY del usuario de GTMetrix
TEST_LOCATION="6" # 6 es Brasil // Disponibles: https://gtmetrix.com/api/0.1/locations
TEST_BROWSER="3" # 3 es Chrome // Disponibles: https://gtmetrix.com/api/0.1/browsers

API_URL="https://gtmetrix.com/api/0.1" # URL de la API de GTMetrix
API_RUN_TEST_ENDPOINT="${API_URL}/test" # Endpoint para ejecutar un nuevo test en la API de GTMetrix

######## Fin Configuracion ########

CURRENT_TIMESTAMP=$(date +"%s")

TEMPFILE_JSON_RUN_TEST="${CURRENT_TIMESTAMP}_run_test.json"
TEMPFILE_JSON_RESULT_TEST="${CURRENT_TIMESTAMP}_result_test.json"
TEMPFILE_PDF_REPORT="${CURRENT_TIMESTAMP}_full_report.pdf"

function run_test() {
	echo "Ejecutando test para la URL ${URL_TO_TEST} con el browser id ${TEST_BROWSER} desde la ubicacion ${TEST_LOCATION}"

    curl -o ${TEMPFILE_JSON_RUN_TEST} --user ${API_EMAIL}:${API_KEY} \
    --form url=$1 --form location=${TEST_LOCATION} --form browser=${TEST_BROWSER} \
    ${API_RUN_TEST_ENDPOINT}
    
    API_TEST_URL=$(cat ${TEMPFILE_JSON_RUN_TEST} | jq -r 'if .poll_state_url then .poll_state_url else empty end')
}

function result_test() {
    curl -o ${TEMPFILE_JSON_RESULT_TEST} --user ${API_EMAIL}:${API_KEY} ${API_TEST_URL}
    API_PDF_REPORT_URL=$(cat ${TEMPFILE_JSON_RESULT_TEST} | jq -r 'if .state == "completed" then .resources.report_pdf else empty end')
    API_REPORT_URL=$(cat ${TEMPFILE_JSON_RESULT_TEST} | jq -r 'if .state == "completed" then .results.report_url else empty end')

    if [ -z ${API_PDF_REPORT_URL} ]
    then
        sleep 15
        looprepeat=$((looprepeat+1))
        
        if [[ ${looprepeat} -ge 5 ]]
        then
            echo -e "Error en el resultado del test luego de 5 intentos. JSON con fallo:"
            cat ${TEMPFILE_JSON_RESULT_TEST}
            
            exit 1
        fi
        
        result_test
    fi
}

function download_report() {
	echo "Descargando reporte en PDF desde la URL ${API_PDF_REPORT_URL}"

    curl -o ${TEMPFILE_PDF_REPORT} --user ${API_EMAIL}:${API_KEY} ${API_PDF_REPORT_URL}
    
    if [[ ! -f ${TEMPFILE_PDF_REPORT} ]]
    then
        echo -e "No se pudo descargar el reporte en PDF. JSON con fallo:"
        cat ${TEMPFILE_JSON_RESULT_TEST}
        
        exit 1
    fi
}

function send_slack_report() {
	if [ ! -z "${1}" ]
	then
	    SLACK_MESSAGE=${SLACK_MESSAGE}"

URL del reporte: ${1}"
	fi

	echo "Enviando notificacion por Slack al canal ${SLACK_CHANNEL}"

    curl -F file=@${TEMPFILE_PDF_REPORT} -F "initial_comment=${SLACK_MESSAGE}" -F channels=${SLACK_CHANNEL} -H "Authorization: Bearer ${SLACK_API_TOKEN}" ${SLACK_API_URL}
}

function clean_temp_files() {
	echo "Limpiando archivos temporales"

    for tempfile in $(set | grep -E '^TEMPFILE_' | awk -F= '{print $2}')
    do
        rm -f ${tempfile}
    done
}

# Ejecuto el test
run_test ${URL_TO_TEST}

# Espero 40 segundos antes de chequear si esta listo
sleep 40

# Chequeo el estado del test y si esta listo guardo en variables el link al reporte en PDF y al reporte online
result_test

# Descargo el PDF del reporte con la URL guardada en la variable en result_test
download_report

# Envio el reporte en PDF al canal de Slack y paso como parametro el link al reporte online
send_slack_report ${API_REPORT_URL}

# Elimino todos los archivos temporales (guardados en variables que empiezan con TEMPFILE_
clean_temp_files
