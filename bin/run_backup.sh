#!/bin/bash

# btrfs_restic_backup.sh
#
# Description:
# Takes snapshots of BTRFS subvolumes and sends thethe snapshot content to a Restic repository.
# See README.md for details.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOT_ENV_FILE="$SCRIPT_DIR/../.env"

# checks that required files and directory are present
check_preconditions() {
  if [ ! -e "$DOT_ENV_FILE" ]; then
    echo ".env file not found." >&2
    exit 1
  fi

  # confirm ssh key is present
  if [ ! -e "$SSH_KEYFILE" ]; then
    echo "key file not found." >&2
    exit 1
  fi

  # confirm BTRFS_SNAPSHOTS_DIR exists
  if [ ! -e "$BTRFS_SNAPSHOTS_DIR" ]; then
    echo "$BTRFS_SNAPSHOTS_DIR (BTRFS_SNAPSHOTS_DIR in .env) not found." >&2
    exit 1
  fi
}

# loads env file
load_dot_env() {
  if [ -f "$DOT_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$DOT_ENV_FILE"
  else
    echo ".env file not found." >&2
    exit 1
  fi
}



build_mountpoint_repo_map() {
  # declare -n mountpoint_repo_list=$1

  local -A mountpoint_repo_map

  for entry in "${MOUNTPOINT_REPO_LIST[@]}"; do
    IFS=':' read -r mount_point repo_name <<<"$entry"
    mountpoint_repo_map[$mount_point]=$repo_name
  done

  echo "${mountpoint_repo_map[@]}"
}

create_log_file() {
  # Get the current date and time in the desired format
  current_time=$(date +"%Y_%m_%d_%H_%M_%S_%N")

  # Define the filename with the current time
  filename="restic-${current_time}.log"

  mkdir -p "$LOG_DIR"
  touch "$LOG_DIR"/"$filename"

  export BTRFS_RESTIC_LOG_FILE="$LOG_DIR"/"$filename"
}

# Creates a BTRFS snapshot=
create_btrfs_snapshot() {
  local mount_point=$1
  local snapshot_name=$2
  local destination="${BTRFS_SNAPSHOTS_DIR}/${snapshot_name}"

  # Create the snapshot
  if sudo /usr/bin/btrfs subvolume snapshot "$mount_point" "$destination"; then
  # if [ $? -eq 0 ]; then
    echo "Snapshot of $mount_point created at $destination"
  else
    echo "Failed to create snapshot of $mount_point"
  fi
}

backup_subvol_to_repo() {
  local mount_point=$1
  local repo_name=$2

  echo "Creating local btrfs snapshot"
  create_btrfs_snapshot "$mount_point" "$repo_name"

  cur_repo=sftp:"$RESTIC_SERVER_USER"@"$RESTIC_SERVER":"$RESTIC_REPOS_DIR"/"$repo_name"
  echo "Sending incremental back up of ${BTRFS_SNAPSHOTS_DIR}/${repo_name} to ${cur_repo}"
  export RESTIC_PASSWORD_FILE="$RESTIC_REPOS_PASSWORD_FILE" 
  "$RESTIC_BINARY" -r "${cur_repo}" --verbose backup "${BTRFS_SNAPSHOTS_DIR}/${repo_name}"
  unset "$RESTIC_REPOS_PASSWORD_FILE"
  sudo /usr/bin/btrfs subvolume delete "${BTRFS_SNAPSHOTS_DIR}/${repo_name}"

}

# Takes snapshots and sends to Restic repo
backup() {

  # Loop through the mount points and create snapshots
  for entry in "${MOUNTPOINT_REPO_LIST[@]}"; do
    IFS=':' read -r mount_point repo_name <<<"$entry"
    backup_subvol_to_repo "$mount_point" "$repo_name"
  done

}

# Calls backup() with logging mode specified in env file
run_backup () {
  if [[ "$TIMESTAMP_LOG" == true ]]; then
  backup 2>&1 | tee >(ts '[%Y-%m-%d %H:%M:%.S]' >> "$BTRFS_RESTIC_LOG_FILE")
else
  backup 2>&1
fi
}

load_dot_env
check_preconditions
create_log_file
run_backup
# build_mountpoint_repo_map 