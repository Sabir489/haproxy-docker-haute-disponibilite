#!/bin/bash
#
# watchdog.sh — Surveille haproxy et bascule automatiquement
# vers haproxy-backup (sur le port 80) en cas de panne.
#
# NOTE PFE : ceci simule un mécanisme de failover simplifié.
# Ce n'est PAS du vrai VRRP (pas de bascule au niveau IP), mais ça
# démontre le principe de redondance du load balancer sans nécessiter
# plusieurs machines physiques/VMs. Limitation assumée et documentée.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_URL="http://localhost:80"
MAX_FAILS=3
CHECK_INTERVAL=3
FAIL_COUNT=0

# Nom du réseau Docker créé par docker compose (à adapter si besoin,
# vérifier avec: docker network ls | grep lb_net)
NETWORK_NAME=$(docker network ls --format '{{.Name}}' | grep lb_net | head -n1)

echo "[watchdog] Démarrage de la surveillance de haproxy (réseau: $NETWORK_NAME)"
echo "[watchdog] Vérification toutes les ${CHECK_INTERVAL}s, bascule après ${MAX_FAILS} échecs"

while true; do
    if curl -sf --max-time 2 "$MASTER_URL" > /dev/null; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "[watchdog] $(date '+%H:%M:%S') - échec de santé master ($FAIL_COUNT/$MAX_FAILS)"
    fi

    if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
        echo "[watchdog] $(date '+%H:%M:%S') - MASTER indisponible. Bascule vers BACKUP sur le port 80..."

        docker rm -f haproxy > /dev/null 2>&1
        docker rm -f haproxy-active > /dev/null 2>&1

        docker run -d --name haproxy-active \
            --network "$NETWORK_NAME" \
            -p 80:80 -p 8405:8404 \
            -v "$SCRIPT_DIR/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
            haproxy:2.8-alpine > /dev/null

        echo "[watchdog] Bascule terminée : le trafic sur le port 80 est maintenant géré par BACKUP."
        echo "[watchdog] Arrêt du watchdog (bascule effectuée une seule fois pour cette démo)."
        break
    fi

    sleep "$CHECK_INTERVAL"
done
