#!/bin/zsh
SECONDS=0
echo "---------------------------------------------------"

echo "Pull latest pihole blocklists"
docker exec pihole pihole updateGravity

echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"