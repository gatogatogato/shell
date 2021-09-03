#!/bin/zsh
SECONDS=0
COMPOSE_FILE=/tmp/docker-compose-changedetection.io.yml
ALL_LINES=$(cat <<'END_HEREDOC'
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
version: "3"
services:
  changedetection.io:
    container_name: changedetection.io
    image: dgtlmoon/changedetection.io
    hostname: changedetection.io
    volumes:
      - changedetection-data:/datastore
    ports:
      - "5000:5000/tcp"
    restart: unless-stopped
volumes:
  changedetection-data:
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
END_HEREDOC
)
echo "$ALL_LINES" > ${COMPOSE_FILE}

echo "---------------------------------------------------"

echo "Docker compose according to compose file"
docker-compose --file ${COMPOSE_FILE} up --detach

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"