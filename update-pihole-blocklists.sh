#!/bin/zsh
SECONDS=0
echo "---------------------------------------------------"
pihole -up
pihole -g
echo "---------------------------------------------------"
echo "Update took ${SECONDS} seconds to finish."
echo "---------------------------------------------------"