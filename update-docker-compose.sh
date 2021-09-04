#!/bin/zsh
SECONDS=0
COMPOSE_FILE=/tmp/docker-compose-all.yml
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
      - /home/pi/dockerData/heimdall-data/config:/config
    ports:
      - 80:80
      - 443:443
    restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  nginx:
    image: nginx:latest
    container_name: nginx
    volumes:
      - /home/pi/dockerData/nginx-data/html:/usr/share/nginx/html
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
    restart: always
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  prowlarr:
      image: ghcr.io/linuxserver/prowlarr:develop
      container_name: prowlarr
      environment:
        - PUID=1000
        - PGID=1000
        - TZ=Europe/London
      volumes:
        - /home/pi/dockerData/prowlarr-data/config:/config
      ports:
        - 9696:9696
      restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  bazarr:
    image: ghcr.io/linuxserver/bazarr
    container_name: bazarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    volumes:
      - /home/pi/dockerData/bazarr-data/config:/config
      - /home/pi/dockerData/movies:/movies #optional
      - /home/pi/dockerData/tvseries:/tv #optional
    ports:
      - 6767:6767
    restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  couchpotato:
    image: adrianmo/rpi-couchpotato
    container_name: couchpotato
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    volumes:
      - /home/pi/dockerData/couchpotato-data/config:/config
      - /home/pi/dockerData/downloads:/downloads
      - /home/pi/dockerData/movies:/movies
    ports:
      - 5050:5050
    restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  sonarr:
    image: ghcr.io/linuxserver/sonarr
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    volumes:
      - /home/pi/dockerData/sonarr-data/config:/config
      - /home/pi/dockerData/tvseries:/tv #optional
      - /home/pi/dockerData/downloads:/downloads #optional
    ports:
      - 8989:8989
    restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  lidarr:
    image: ghcr.io/linuxserver/lidarr
    container_name: lidarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/London
    volumes:
      - /home/pi/dockerData/lidarr-data/config:/config
      - /home/pi/dockerData/music:/music #optional
      - /home/pi/dockerData/downloads:/downloads #optional
    ports:
      - 8686:8686
    restart: unless-stopped
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
END_HEREDOC
)
echo "$ALL_LINES" > ${COMPOSE_FILE}

echo "---------------------------------------------------"
echo "Docker compose file: ${COMPOSE_FILE}"
echo "Pull latest images"
docker-compose --file ${COMPOSE_FILE} pull

echo "Docker compose according to compose file"
docker-compose --file ${COMPOSE_FILE} up --detach

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"