#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Adrian-RDA
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/maziggy/bambuddy

APP="Bambuddy"
var_tags="${var_tags:-media;3d-printing}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bambuddy ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  ensure_dependencies ffmpeg

  local RELEASE_TAG=""

  if [[ "${VERBOSE:-no}" == "yes" ]]; then
    if RELEASE_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
      --title "SELECT RELEASE TYPE" \
      --radiolist "\nSelect ${APP} build type:\n\nUse SPACE to select, ENTER to confirm." \
      12 60 2 \
      "latest"     "Latest Stable Release" ON \
      "prerelease" "Prerelease / Daily Build" OFF \
      3>&1 1>&2 2>&3); then
      if [[ "$RELEASE_CHOICE" == "prerelease" ]]; then
        msg_info "Fetching latest prerelease"
        RELEASE_TAG=$(curl -fsSL "https://api.github.com/repos/maziggy/bambuddy/releases" \
          | jq -r '[.[] | select(.prerelease==true)][0].tag_name // empty')
        if [[ -n "$RELEASE_TAG" ]]; then
          export var_appversion="$RELEASE_TAG"
          msg_ok "Selected prerelease: ${RELEASE_TAG}"
        else
          msg_warn "No prerelease builds found; defaulting to latest stable."
        fi
      fi
    fi
  fi

  # check_for_gh_release filters out prereleases, so for the prerelease path
  # we skip it and let fetch_and_deploy_gh_release handle the version check internally.
  local do_update="false"
  if [[ -n "$RELEASE_TAG" ]]; then
    do_update="true"
  elif check_for_gh_release "bambuddy" "maziggy/bambuddy"; then
    do_update="true"
  fi

  if [[ "$do_update" == "true" ]]; then
    msg_info "Stopping Service"
    systemctl stop bambuddy
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration and Data"
    cp /opt/bambuddy/.env /opt/bambuddy.env.bak
    cp -r /opt/bambuddy/data /opt/bambuddy_data_bak
    [[ -f /opt/bambuddy/bambuddy.db ]] && cp /opt/bambuddy/bambuddy.db /opt/bambuddy.db.bak
    [[ -f /opt/bambuddy/bambutrack.db ]] && cp /opt/bambuddy/bambutrack.db /opt/bambutrack.db.bak
    [[ -d /opt/bambuddy/archive ]] && cp -r /opt/bambuddy/archive /opt/bambuddy_archive_bak
    msg_ok "Backed up Configuration and Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "bambuddy" "maziggy/bambuddy" "tarball" "${RELEASE_TAG:-latest}" "/opt/bambuddy"

    msg_info "Updating Python Dependencies"
    cd /opt/bambuddy
    $STD uv venv --clear
    $STD uv pip install -r requirements.txt
    msg_ok "Updated Python Dependencies"

    msg_info "Rebuilding Frontend"
    cd /opt/bambuddy/frontend
    $STD npm install
    $STD npm run build
    msg_ok "Rebuilt Frontend"

    msg_info "Restoring Configuration and Data"
    mkdir -p /opt/bambuddy/data
    cp /opt/bambuddy.env.bak /opt/bambuddy/.env
    cp -r /opt/bambuddy_data_bak/. /opt/bambuddy/data/
    [[ -f /opt/bambuddy.db.bak ]] && cp /opt/bambuddy.db.bak /opt/bambuddy/bambuddy.db
    [[ -f /opt/bambutrack.db.bak ]] && cp /opt/bambutrack.db.bak /opt/bambuddy/bambutrack.db
    if [[ -d /opt/bambuddy_archive_bak ]]; then
      mkdir -p /opt/bambuddy/archive
      cp -r /opt/bambuddy_archive_bak/. /opt/bambuddy/archive/
    fi
    rm -f /opt/bambuddy.env.bak /opt/bambuddy.db.bak /opt/bambutrack.db.bak
    rm -rf /opt/bambuddy_data_bak /opt/bambuddy_archive_bak
    msg_ok "Restored Configuration and Data"

    msg_info "Starting Service"
    systemctl start bambuddy
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start

# In Advanced Install mode, offer version selection before container creation
if [[ "${METHOD:-}" == "advanced" ]]; then
  if RELEASE_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "SELECT RELEASE TYPE" \
    --radiolist "\nSelect ${APP} build type:\n\nUse SPACE to select, ENTER to confirm." \
    12 60 2 \
    "latest"     "Latest Stable Release" ON \
    "prerelease" "Prerelease / Daily Build" OFF \
    3>&1 1>&2 2>&3); then
    if [[ "$RELEASE_CHOICE" == "prerelease" ]]; then
      PRERELEASE_TAG=$(curl -fsSL "https://api.github.com/repos/maziggy/bambuddy/releases" \
        | jq -r '[.[] | select(.prerelease==true)][0].tag_name // empty')
      if [[ -n "$PRERELEASE_TAG" ]]; then
        export var_appversion="$PRERELEASE_TAG"
        msg_ok "Selected prerelease: ${PRERELEASE_TAG}"
      else
        msg_warn "No prerelease builds found; defaulting to latest stable."
      fi
    fi
  fi
fi

build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
