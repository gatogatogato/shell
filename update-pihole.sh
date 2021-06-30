#!/bin/zsh
SECONDS=0
PIHOLE_BASE=/home/pi/pihole-data
echo "---------------------------------------------------"
echo "Pull latest PiHole"
docker pull pihole/pihole:latest

echo "Remove current PiHole"
docker rm -f pihole

echo "Start new container from latest image"
docker run -d \
--name pihole \
-p 53:53/tcp -p 53:53/udp \
-p 8001:80 \
-e TZ="Switzerland/Zurich" \
-v "${PIHOLE_BASE}/etc-pihole/:/etc/pihole/" \
-v "${PIHOLE_BASE}/etc-dnsmasq.d/:/etc/dnsmasq.d/" \
--dns=127.0.0.1 --dns=1.1.1.1 \
--restart=unless-stopped \
--hostname pi.hole \
-e VIRTUAL_HOST="pi.hole" \
-e PROXY_LOCATION="pi.hole" \
-e ServerIP="127.0.0.1" \
pihole/pihole:latest

echo "Wait 10s for startup..."
sleep 10

echo "Set password for admin interface"
docker exec -it pihole pihole -a -p Nq6owAdprdst9tcYCFQLxLPfYkX3prBaqLionkYW

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"