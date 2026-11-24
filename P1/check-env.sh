#!/bin/sh
# Verifie que la machine a ce qu'il faut pour lancer le projet.
# Ne modifie rien : affiche une ligne par verification.

missing=0

has_word() {
  wanted="$1"
  shift
  for word in "$@"; do
    if [ "$word" = "$wanted" ]; then
      return 0
    fi
  done
  return 1
}

check_tool() {
  tool="$1"
  if command -v "$tool" > /dev/null 2>&1; then
    echo "[ OK ] $tool"
  else
    echo "[FAIL] $tool est absent"
    missing=1
  fi
}

check_docker_service() {
  if docker info > /dev/null 2>&1; then
    echo "[ OK ] le service Docker repond"
  else
    echo "[FAIL] le service Docker ne repond pas"
    missing=1
  fi
}

# Un groupe ajoute a un compte n'est actif qu'a la prochaine ouverture de session.
check_group() {
  group="$1"
  if ! getent group "$group" > /dev/null 2>&1; then
    return
  fi
  if [ "$(id -u)" -eq 0 ]; then
    echo "[ OK ] groupe $group (inutile pour root)"
    return
  fi
  user=$(id -un)
  account_groups=$(id -nG "$user")
  session_groups=$(id -nG)
  if has_word "$group" $session_groups; then
    echo "[ OK ] groupe $group"
  elif has_word "$group" $account_groups; then
    echo "[FAIL] groupe $group : inscrit, mais il faut rouvrir la session"
    missing=1
  else
    echo "[FAIL] groupe $group : $user n'est pas inscrit"
    missing=1
  fi
}

echo "Outils"
check_tool docker
check_tool gns3
check_tool gns3server
check_tool ubridge
check_tool wireshark
check_tool telnet

echo "Docker"
check_docker_service

echo "Groupes"
check_group docker
check_group ubridge
check_group wireshark

if [ "$missing" -eq 0 ]; then
  echo "La machine est prete."
else
  echo "Il manque des elements : voir les lignes [FAIL]."
fi
