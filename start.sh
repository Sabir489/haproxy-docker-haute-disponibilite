#!/bin/bash
# start.sh — Demarrage fiable de la plateforme PFE.
# Nettoie les conteneurs residuels, libere le port 80, puis demarre tout.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "== 1/4 : nettoyage des conteneurs residuels =="
docker rm -f haproxy-active > /dev/null 2>&1 && echo "  haproxy-active supprime"
docker compose down --remove-orphans > /dev/null 2>&1
echo "  termine"

echo "== 2/4 : verification du port 80 =="
OCCUPANT=$(docker ps -a --format '{{.Names}} {{.Ports}}' | grep '0.0.0.0:80->' | awk '{print $1}')
if [ -n "$OCCUPANT" ]; then
    echo "  conteneur $OCCUPANT occupe le port 80, suppression..."
    docker rm -f "$OCCUPANT" > /dev/null 2>&1
fi
if ss -tln 2>/dev/null | grep -q ':80 '; then
    echo "  ATTENTION : le port 80 reste occupe par un processus systeme."
    echo "  Redemarrez Docker Desktop, ou basculez sur le port 8090 (voir README)."
fi
echo "  termine"

echo "== 3/4 : demarrage de la plateforme =="
docker compose up -d --build || exit 1

echo "== 4/4 : verification apres 12 secondes =="
sleep 12
ATTENDUS="web1 web2 web3 haproxy haproxy-backup prometheus grafana"
MANQUANTS=""
for c in $ATTENDUS; do
    docker ps --format '{{.Names}}' | grep -qx "$c" || MANQUANTS="$MANQUANTS $c"
done

echo ""
docker ps --format 'table {{.Names}}\t{{.Status}}'
echo ""

if [ -n "$MANQUANTS" ]; then
    echo "ECHEC : conteneur(s) arrete(s) :$MANQUANTS"
    for c in $MANQUANTS; do
        echo "--- journal de $c ---"
        docker compose logs "$c" 2>/dev/null | tail -n 6
    done
    exit 1
fi

echo "SUCCES : les 7 conteneurs fonctionnent."
echo ""
echo "  Application   : http://localhost:80"
echo "  Statistiques  : http://localhost:8405/stats"
echo "  Secours       : http://localhost:8082"
echo "  Prometheus    : http://localhost:9091"
echo "  Grafana       : http://localhost:3000"
echo ""
echo "Test de repartition :"
for i in 1 2 3 4 5 6; do
    curl -s --max-time 2 localhost:80 | grep -o 'numéro [0-9]' || echo "  (pas de reponse)"
done
