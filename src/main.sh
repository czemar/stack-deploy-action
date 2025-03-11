#!/usr/bin/env bash

set -e

echo "Running: ${0} as: $(whoami) in: $(pwd)"

echo "Repository files:"
ls -la /github/workspace

function cleanup_trap() {
    _ST="$?"
    if [[ "${_ST}" != "0" ]]; then
        echo -e "\u001b[31;1mScript Exited with Error: ${_ST}"
    fi
    if [ -z "${INPUT_SSH_KEY}" ];then
        echo -e "\u001b[35mCleaning Up authorized_keys on: ${INPUT_HOST}"
        ssh -p "${INPUT_PORT}" "${INPUT_USER}@${INPUT_HOST}" \
            "sed -i '/docker-stack-deploy-action/d' ~/.ssh/authorized_keys"
    fi
    if [[ "${_ST}" == "0" ]]; then
        echo -e "\u001b[32;1mFinished Success."
    fi
    exit "${_ST}"
}

echo -e "\u001b[36mCreating ssh directory"

mkdir -p /root/.ssh

echo -e "\u001b[36mSetting Permissions on ssh directory"
chmod 0700 /root/.ssh

echo -e "\u001b[36mAdding Host to known_hosts"
echo "Port: ${INPUT_PORT} Host: ${INPUT_HOST}"

ssh-keyscan -p "${INPUT_PORT}" -H "${INPUT_HOST}" >> /root/.ssh/known_hosts

echo -e "\u001b[36mChecking for SSH Key or Password"

if [ -z "${INPUT_SSH_KEY}" ];then
    echo -e "\u001b[36mCreating and Copying SSH Key to: ${INPUT_HOST}"
    ssh-keygen -q -f /root/.ssh/id_rsa -N "" -C "docker-stack-deploy-action"
    eval "$(ssh-agent -s)"
    ssh-add /root/.ssh/id_rsa

    sshpass -p "${INPUT_PASS}" \
        ssh-copy-id -p "${INPUT_PORT}" -i /root/.ssh/id_rsa \
            "${INPUT_USER}@${INPUT_HOST}"
else
    echo -e "\u001b[36mAdding SSH Key to SSH Agent"
    echo "${INPUT_SSH_KEY}" > /root/.ssh/id_rsa
    chmod 0600 /root/.ssh/id_rsa
    eval "$(ssh-agent -s)"
    ssh-add /root/.ssh/id_rsa
fi

echo -e "\u001b[36mSetting up Trap for Cleanup"

trap cleanup_trap EXIT HUP INT QUIT PIPE TERM

echo -e "\u001b[36mVerifying Docker and Setting Context."
ssh -p "${INPUT_PORT}" "${INPUT_USER}@${INPUT_HOST}" "docker info" || echo "Error: Unable to retrieve Docker info"

if [ -n "$(docker context ls --format '{{.Name}}' | grep remote)" ];then
    echo -e "\u001b[36mDocker Context Exists: remote"
    docker context use default
    docker context rm remote --force
fi

echo -e "\u001b[36mCreating Docker Context: remote"

docker context create remote --docker "host=ssh://${INPUT_USER}@${INPUT_HOST}:${INPUT_PORT}"
docker context ls
docker context use remote

echo -e "\u001b[36mCopying Docker Compose File to Remote Host: ${INPUT_HOST}"

if [ -n "${INPUT_ENV_FILE}" ];then
    echo -e "\u001b[36mSourcing Environment File: ${INPUT_ENV_FILE}"
    pwd
    ls -la
    stat "${INPUT_ENV_FILE}"
    set -a
    # shellcheck disable=SC1090
    source "${INPUT_ENV_FILE}"
    # echo TRAEFIK_HOST: "${TRAEFIK_HOST}"
    # export ENV_FILE="${INPUT_ENV_FILE}"
fi

if [ -n "${INPUT_ENV}" ];then
    echo -e "\u001b[36mSetting Environment Variables"
    echo "${INPUT_ENV}" > /tmp/env
    stat /tmp/env
    set -a
    # shellcheck disable=SC1090
    source /tmp/env
fi

echo -e "\u001b[36mDeploying Stack: \u001b[37;1m${INPUT_NAME}"
docker stack deploy -c "${INPUT_FILE}" "${INPUT_NAME}"
