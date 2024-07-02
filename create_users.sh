#!/bin/bash

# Log file for user management actions
LOG_FILE="/var/log/user_management.log"

# Secure password storage file (restricted access)
PASSWORD_FILE="/var/secure/user_passwords.txt"

# Function to log messages to the log file
log_message() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check if the script is run with a file argument
if [ $# -ne 1 ]; then
  echo "Usage: $0 <user_list_file>"
  exit 1
fi

# Get the absolute path of the input file
USER_LIST_FILE=$(realpath "$1")

# Check if the log file exists and create it if not
if [ ! -f "$LOG_FILE" ]; then
  touch "$LOG_FILE"
fi

# Check if the password file exists and create it with restricted access if not
if [ ! -f "$PASSWORD_FILE" ]; then
  mkdir -p /var/secure
  touch "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
fi

# Process user list file
while IFS=';' read -r username groups; do
  # Trim whitespace
  username=$(echo "$username" | xargs)
  groups=$(echo "$groups" | xargs)

  # Skip empty lines
  [ -z "$username" ] && continue

  # Create user's personal group if it doesn't exist
  if ! getent group "$username" > /dev/null; then
    log_message "Creating group: $username"
    groupadd "$username" &>> "$LOG_FILE"
  else
    log_message "Group $username already exists"
  fi

  # Check if user already exists
  if id "$username" &> /dev/null; then
    log_message "Error: User '$username' already exists. Skipping..."
    continue
  fi

  # Create user with primary group set to user's personal group and create home directory
  log_message "Creating user: $username"
  useradd -m -g "$username" "$username" &>> "$LOG_FILE"

  # Generate random password
  password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

  # Set user password
  log_message "Setting password for $username"
  echo "$username:$password" | chpasswd &>> "$LOG_FILE"

  # Initialize groups list with personal group
  user_groups="$username"

  # Process additional groups (comma-separated)
  if [ ! -z "$groups" ]; then
    IFS=',' read -ra ADDITIONAL_GROUPS <<< "$groups"
    for group in "${ADDITIONAL_GROUPS[@]}"; do
      # Trim whitespace
      group=$(echo "$group" | xargs)
      
      # Create group if it doesn't exist
      if ! getent group "$group" > /dev/null; then
        log_message "Creating group: $group"
        groupadd "$group" &>> "$LOG_FILE"
      else
        log_message "Group $group already exists"
      fi
      
      # Add user to the group
      log_message "Adding user $username to group: $group"
      usermod -aG "$group" "$username" &>> "$LOG_FILE"

      # Add to user groups list
      user_groups+=", $group"
    done
  fi

  # Store username and password securely
  echo "$username,$password" >> "$PASSWORD_FILE"

done < "$USER_LIST_FILE"

log_message "User creation process completed."
