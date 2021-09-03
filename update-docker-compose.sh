#!/bin/zsh
SECONDS=0
COMPOSE_FILE=/tmp/docker-compose-all.yml
PORTAINER_PASSWORD_FILE=/tmp/portainer-password.txt
PORTAINER_PASSWORD=ZPqcNM2v6Gnx8Q7ygbVF
PIHOLE_PASSWORD=Nq6owAdprdst9tcYCFQLxLPfYkX3prBaqLionkYW
ALL_LINES=$(cat <<'END_HEREDOC'
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
version: "3"
# More info at https://github.com/pi-hole/docker-pi-hole/ and https://docs.pi-hole.net/
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "67:67/udp"
      - "8001:80/tcp"
    environment:
      TZ: 'Europe/Berlin'
      WEBPASSWORD: 'Nq6owAdprdst9tcYCFQLxLPfYkX3prBaqLionkYW'
      VIRTUAL_HOST: "pi.hole"
      PROXY_LOCATION: "pi.hole"
      ServerIP: "127.0.0.1"
      DNSMASQ_LISTENING: "all"
    # Volumes store your data between container upgrades
    volumes:
      - '/home/pi/dockerData/pihole-data/etc-pihole/:/etc/pihole/'
      - '/home/pi/dockerData/pihole-data/etc-dnsmasq.d/:/etc/dnsmasq.d/'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
    dns: 127.0.0.1
    dns: 1.1.1.1
    hostname: pi.hole
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  heimdall:
    image: ghcr.io/linuxserver/heimdall
    container_name: heimdall
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Berlin
    volumes:
      - /home/pi/dockerData/heimdall-data/:/config
    ports:
      - 80:80
      - 443:443
    restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  nginx:
    image: nginx:latest
    container_name: nginx
    volumes:
      - /home/pi/dockerData/nginx-data/:/usr/share/nginx/html
    ports:
      - 8000:80
    restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  portainer:
    image: portainer/portainer:latest
    container_name: portainer
    environment:
      - TZ=Europe/Berlin
    volumes:
      - /home/pi/dockerData/portainer-data/:/data
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - 9000:9000
    command: --admin-password-file /tmp/portainer-password.txt
    restart: always
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
END_HEREDOC
)
echo "$ALL_LINES" > ${COMPOSE_FILE}

docker run --rm httpd:2.4-alpine htpasswd -nbB admin "${PORTAINER_PASSWORD}" | cut -d ":" -f 2 > ${PORTAINER_PASSWORD_FILE}

echo "---------------------------------------------------"

echo "Pull latest images"
#docker pull pihole/pihole:latest
docker-compose --file ${COMPOSE_FILE} pull

echo "Docker compose according to compose file"
docker-compose --file ${COMPOSE_FILE} up --detach

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"