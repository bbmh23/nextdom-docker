#!/usr/bin/env bash

#get script directory
localDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
#Directory for apache certificate
SSLDIR=apache/ssl/
#Archive containing the nextdom-core project
NEXTDOMTAR=nextdom-dev.tar.gz
#volume for mysql
VOLMYSQL=$(basename $PWD)_mysqldata-prod
#Use zip unstead of git clone
ZIP=N
#Keep volume if Y, recreate otherwise
KEEP=N
#use latest release
RELEASE=N
#Define dockerfile and compose
YML=docker-compose.yml
DKRFILE=${localDir}/apache/Dockerfile
ARMDKRFILE=${DKRFILE}.armhf
#get cpu architecture
ARCHI=$(dpkg --print-architecture)

#fonctions
usage(){
    echo -e "\n$0: [d,m,(u|p)]\n\twithout option, container is built from github sources and has no access to devices"
    echo -e "\tk\tcontainer volumes are not recreated, but reused ( keep previous data intact)"
    echo -e "\tp\tcontainer has access to all devices (privileged: not recommended)"
    echo -e "\tu\tcontainer has access to ttyUSB0"
    echo -e "\tr\tuse latest release instead of branch"
    echo -e "\th\tThis help"
    exit 0
}

generateCert(){
    echo -e "<I> Creating SSL self-signed certificat in /etc/nextdom/ssl/"
    if [ ! -d "${SSLDIR}" ]
     then
      mkdir -p ${SSLDIR}
    fi
    openssl genrsa -out ${SSLDIR}nextdom.key 2048 2>&1
    openssl req -new -key ${SSLDIR}nextdom.key -out ${SSLDIR}nextdom.csr -subj "/C=FR/ST=Paris/L=Paris/O=Global Security/OU=IT Department/CN=example.com" 2>&1
    openssl x509 -req -days 3650 -in ${SSLDIR}nextdom.csr -signkey ${SSLDIR}nextdom.key -out ${SSLDIR}nextdom.crt 2>&1
}

createVolumes(){
for volname in ${VOLMYSQL}
    do
    VOL2DELETE=$(docker volume ls -qf name=${volname})
    [[ ! -z ${VOL2DELETE} ]] && echo **deleting volume $(docker volume rm ${VOL2DELETE})
    echo *creating volume $(docker volume create ${volname})
    done
}

updateEnvWebRelease(){
    RELEASE=$1
    #fetch last release once to preserve api while testing
    #[[ ! -f a ]] && curl -sH "Authorization: token $(cat ../githubtoken.txt)" "https://api.github.com/repos/Sylvaner/nextdom-core/releases/latest" >a ; jsonGit=$(cat a)
    #fetch last release at each run
    jsonGit=$(curl -s "https://api.github.com/repos/Nextdom/nextdom-core/releases/latest")
    gitTag=$(echo $jsonGit | grep -oP "\"tag_name\": \"([^\"]*)\"" | cut -f4 -d'"')
    gitTarBall=$(echo -e $jsonGit | grep -oP "\"zipball_url\": \"([^\"]*)\"" | cut -f4 -d'"')

    #By default remove Tag
    for file in envWeb .env
        do
            sed -i 's/VERSION=.*//g' ${file}
            sed -i '/^$/d' ${file}
        done

    #If RELEASE is requested, then use last release
    if [[ "Y" == "${RELEASE}" ]]; then
        if [[ -z ${gitTag} ]]; then
                echo github api not available ? github release var is empty
                echo VERSION:$VERSION / gitTag:$gitTag
                exit -1
        fi
        echo -e "\nAdding latest release (${gitTag}) to envWeb"
        #echo gitTar: $gitTarBall
        echo "VERSION=${gitTag}" | tee -a envWeb
        echo "VERSION=${gitTag}" | tee -a .env
        else 
        sed -i "/VERSION=/d" .env
        sed -i "/VERSION=/d" envWeb
     fi
}

generateArmHfDockerfile(){
    if [ "xarmhf" = "x${ARCHI}" ]; then
        sed 's#amd64-debian#armv7hf-debian#' ${DKRFILE} > ${ARMDKRFILE}
        sed -i 's#amd64-debian#armv7hf-debian#' ${ARMDKRFILE}
        else
          #replace strecth amd for stretch  rmhf
        sed 's#FROM balenalib/amd64-debian:stretch-run as builder#FROM balenalib/armv7hf-debian:stretch-build as builder\
RUN [ "cross-build-start" ]#' ${DKRFILE} > ${ARMDKRFILE}
        sed -i 's#FROM balenalib/amd64-debian:stretch-run as prod#RUN [ "cross-build-end" ]\
FROM balenalib/armv7hf-debian:stretch-run as prod\
RUN [ "cross-build-start" ]#' ${ARMDKRFILE}
          #replace strecth amd for stretch  rmhf
             #FROM balenalib/amd64-debian:buster-build as builder
        sed 's#FROM balenalib/amd64-debian:buster-build as builder#FROM balenalib/armv7hf-debian:buster-build as builder\
RUN [ "cross-build-start" ]#' ${DKRFILE} > ${ARMDKRFILE}
        sed -i 's#FROM balenalib/amd64-debian:buster-run as prod#RUN [ "cross-build-end" ]\
FROM balenalib/armv7hf-debian:buster-run as prod\
RUN [ "cross-build-start" ]#' ${ARMDKRFILE}
#' ${ARMDKRFILE}
        sed -i 's#FROM balenalib/amd64-debian:buster-run as prod#FROM balenalib/armv7hf-debian:buster-run as prod#' ${ARMDKRFILE}

        echo 'RUN [ "cross-build-end" ]' | tee -a ${ARMDKRFILE}
    fi
    echo "****** Check ARM docker file ********"
    grep -E "FROM|RUN \[" ${ARMDKRFILE}
    echo "*************************************"
}


#main
source .env
source envMysql

#getOptions
while getopts ":hkpuzr" opt; do
    case $opt in
        k) echo -e "\nkeep docker volume (database)"
        KEEP=Y
        ;;
        h) usage
        ;;
        p) echo -e "\ndocker will have access to all devices\n"
        YML="docker-compose.yml -f docker-compose-privileged.yml"
        ;;
        u) echo -e "\n docker will have access to ttyUSB0\n"
        YML="docker-compose.yml -f docker-compose-devices.yml"
        ;;
        z) echo -e "\nMaking a zip in docker"
        ZIP=Y
        ;;
        r) echo -e "\nUse latest release"
        RELEASE=Y
        ;;
        \?) echo "${ROUGE}Invalid option -$OPTARG${NORMAL}" >&2
        ;;
    esac
done

#generate auto-signed certificate
[[ ! -f ${SSLDIR}nextdom.key ]] && generateCert

updateEnvWebRelease ${RELEASE}

#generate ARM dockerfile
[[ ! -f ${DKRFILE} ]] && echo -e "\nError, Dockerfile is not found\n" && exit -1
rm ${ARMDKRFILE}
generateArmHfDockerfile

if [ "${ARCHI}" == "armhf" ]; then
  YML=docker-compose-armhf.yml
  fi

# extract local project to container volume
if [ "Y" == ${KEEP} ]; then
    # stop running container
    docker-compose -f ${YML} stop
    else
    # stop container and remove volume
    docker-compose -f ${YML} down -v --remove-orphans
fi

# build
CACHE=""
#CACHE="--no-cache"
bVer=""
[[ ! -z  ${gitTag} ]] && bVer=" --build-arg VERSION=${gitTag}"
echo "using tag: $gitTag, URL:${URLGIT}, init: ${initSh}";


#Build image according to architecture
docker-compose -f ${YML} build ${CACHE} ${bVer} --build-arg BRANCH=master --build-arg URLGIT=${URLGIT} --build-arg initSh=${initSh} web

#if on a amd64 architecture try to cross build armhf version
if [ "${ARCHI}" == "amd64" ]; then
  YML2=docker-compose-armhf.yml
  #docker build ${CACHE} --build-arg BRANCH=master --build-arg URLGIT=${URLGIT} --build-arg initSh=${initSh} -t nextdom-web:latest-armhf -f ${ARMDKRFILE} .
fi

# prepare volumes
docker-compose -f ${YML} up --no-start

if [ "Y" == ${ZIP} ]; then
        echo zipping ${NEXTDOMTAR}
        docker run --rm -v $(pwd):/backup ubuntu bash -c "tar -zcf /backup/${NEXTDOMTAR} -C /var/www/html/ -C /etc/nextdom -C /var/lib/nextdom -C /usr/share/nextdom"
fi

#disable sha2_password authentification
docker-compose exec mysql sed -i "s/# default/default/g" /etc/my.cnf

#docker-compose -f ${YML} up --remove-orphans
#Place tags
#docker tag nextdom-web:latest edgd1er/nextdom-web:latest-amd64
#docker tag nextdom-web:latest-armhf edgd1er/nextdom-web:latest-armhf
