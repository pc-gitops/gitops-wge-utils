#!/usr/bin/env bash

# Utility for configuring vault
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] " >&2
    echo "This script will configure vault" >&2
}

function args() {

  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  tls_skip=""
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--tls-skip") tls_skip="-tls-skip-verify";;
          "--debug") set -x;;
               "-h") usage; exit;;
           "--help") usage; exit;;
               "-?") usage; exit;;
        *) if [ "${arg_list[${arg_index}]:0:2}" == "--" ];then
               echo "invalid argument: ${arg_list[${arg_index}]}" >&2
               usage; exit
           fi;
           break;;
    esac
    (( arg_index+=1 ))
  done
}

args "$@"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/envs.sh

source $(local_or_global resources/github-config.sh)
source resources/github-secrets.sh

export VAULT_ADDR="https://vault.${local_dns}"
export VAULT_TOKEN="$(jq -r '.root_token' resources/.vault-init.json)"
export DEX_URL="https://dex.${local_dns}"
export GITHUB_AUTH_ORG=pc-gitops

set +e

vault auth $tls_skip enable oidc

vault write $tls_skip auth/oidc/config \
  oidc_discovery_url="$DEX_URL" \
  oidc_client_id="vault" \
  oidc_client_secret="$VAULT_DEX_CLIENT_SECRET" \
  default_role="default"

vault write $tls_skip auth/oidc/role/default \
  allowed_redirect_uris="$VAULT_ADDR/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  user_claim="preferred_username" \
  groups_claim="groups" \
  oidc_scopes="profile,groups" \
  token_ttl="12h" \
  token_policies="default"

vault write $tls_skip identity/group name=github-admin policies=admin type=external

github_admin_id=$(vault read identity/group/name/github-admin --format=json | jq -r '.data.id')
accessor_id=$(vault auth $tls_skip list --format=json | jq -r '.["oidc/"].accessor')

vault write $tls_skip identity/group-alias name=$GITHUB_AUTH_ORG canonical_id=$github_admin_id mount_accessor=$accessor_id

