#!/bin/zsh
SECONDS=0
PIHOLE_COMPOSE_FILE=/tmp/docker-compose-pihole.yml
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
      TZ: 'America/Chicago'
      WEBPASSWORD: 'Nq6owAdprdst9tcYCFQLxLPfYkX3prBaqLionkYW'
      VIRTUAL_HOST: "pi.hole"
      PROXY_LOCATION: "pi.hole"
      ServerIP: "127.0.0.1"
    # Volumes store your data between container upgrades
    volumes:
      - './pihole-data/etc-pihole/:/etc/pihole/'
      - './pihole-data/etc-dnsmasq.d/:/etc/dnsmasq.d/'
    # Recommended but not required (DHCP needs NET_ADMIN)
    #   https://github.com/pi-hole/docker-pi-hole#note-on-capabilities
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
    dns: 127.0.0.1
    dns: 1.1.1.1
    hostname: pi.hole
#////////////////////////////////////////////////////////////////////////////////////////////////////////////////
END_HEREDOC
)
echo "$ALL_LINES" > ${PIHOLE_COMPOSE_FILE}

echo "---------------------------------------------------"

echo "Pull latest PiHole"
docker pull pihole/pihole:latest

echo "Docker compose according to compose file"
docker-compose --file ${PIHOLE_COMPOSE_FILE} up --detach

echo "Pull latest blocklists"
docker exec pihole pihole updateGravity

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"