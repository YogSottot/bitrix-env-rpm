#!/bin/bash

# Variables
LOCK_FILE="/var/lib/rpm/.rpm.lock"
SCRIPT_LOCK="/var/run/downgrade_perl_mysql.pid"
LOG_FILE="/opt/webdir/logs/downgrade_perl_mysql.log"
CRON_JOB_FILE="/tmp/downgrade_perl_mysql_cron"
OS=""

# Function to log messages with timestamp
print() {
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" >> "$LOG_FILE"
}

# Operating system detection
get_os() {
    if [ -f /etc/centos-release ]; then
        # For CentOS
        if grep -q "Stream" /etc/centos-release; then
            OS="CentOS Stream"
        else
            OS="CentOS"
        fi
    elif [ -f /etc/redhat-release ]; then
        # For RHEL, Rocky, AlmaLinux
        if grep -q "Rocky" /etc/redhat-release; then
            OS="Rocky Linux"
        elif grep -q "AlmaLinux" /etc/redhat-release; then
            OS="AlmaLinux"
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS="RHEL"
        else
            OS=$(cat /etc/redhat-release | awk '{print $1}')
        fi
    elif [ -f /etc/oracle-release ]; then
        # For Oracle Linux
        OS="Oracle Linux"
    else
        # Try with os-release
        if [ -f /etc/os-release ]; then
            OS=$(grep -oP '(?<=^NAME=")[^"]+' /etc/os-release || grep -oP '(?<=^NAME=)[^"]+' /etc/os-release)
        else
            OS="Unknown"
        fi
    fi
    
    print "Detected operating system: ${OS}"
    return 0
}

# Check concurrency
check_concurrency() {
    if [ -f "$SCRIPT_LOCK" ]; then
        pid=$(cat "$SCRIPT_LOCK")
        if ps -p "$pid" > /dev/null 2>&1; then
            print "Script is already running with PID $pid. Exiting."
            exit 1
        else
            print "Found stale PID file, removing..."
            rm -f "$SCRIPT_LOCK"
        fi
    fi
    
    # Write current PID to lock file
    echo $$ > "$SCRIPT_LOCK"
    print "Started monitoring process with PID $$"
    
    # Register function to remove lock file on exit
    trap 'rm -f "$SCRIPT_LOCK"; print "Removed script lock file for PID $$"' EXIT
    
    return 0
}

# Monitor rpm.lock
monitor_rpm_lock() {
    print "Checking RPM lock status"
    
    # Check for RPM locks using lslocks
    if lslocks | grep -q -E "$LOCK_FILE"; then
        print "RPM is locked. Found lock on RPM database"
        return 1  # RPM is locked
    else
        print "RPM is not locked"
        return 0  # RPM is not locked
    fi
}

# Perform actions after rpm.lock is released
downgrade_perl_dbd_mysql() {

    CURRENT_VERSION=$(rpm -qa --queryformat '%{version}' perl-DBD-MySQL | head -1)
    PACKAGE_NAME="perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
    if [[ ${CURRENT_VERSION} != "4.050" ]]; then
        print "Starting perl-DBD-MySQL downgrade process"
        
        get_os
        
        if [[ ${OS} == 'Rocky Linux' ]]; then
            DOWNLOAD_LINK="https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/Packages/p/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
        elif [[ ${OS} == 'AlmaLinux' ]]; then
            DOWNLOAD_LINK="https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/Packages/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
        elif [[ ${OS} == 'Oracle Linux' ]]; then
            DOWNLOAD_LINK="https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64/getPackage/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
        elif [[ ${OS} == 'CentOS Stream' ]]; then
            DOWNLOAD_LINK="https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages/perl-DBD-MySQL-4.050-13.el9.x86_64.rpm"
        else
            print "Unknown distribution: ${OS}, downgrade not performed"
            return 0
        fi
        
        # Downgrading process
        cd /tmp
        
        # Check if package exists before attempting to remove it
        if [[ -n "$CURRENT_VERSION" ]]; then
            print "Removing current package version: $CURRENT_VERSION"
            rpm -e perl-DBD-MySQL >> "$LOG_FILE" 2>&1
        else
            print "No current version detected, skipping removal step"
        fi
        
        print "Downloading old package: ${DOWNLOAD_LINK}"
        wget ${DOWNLOAD_LINK} >> "$LOG_FILE" 2>&1
        
        if [[ $? -eq 0 ]]; then
            print "Installing package"
            rpm -Uvh ${PACKAGE_NAME} >> "$LOG_FILE" 2>&1
            
            if [[ $? -eq 0 ]]; then
                print "Successfully installed version 4.050"
                # Cleanup
                rm -f /tmp/${PACKAGE_NAME} >> "$LOG_FILE" 2>&1
                return 0
            else
                print "Error installing version 4.050"
                return 1
            fi
        else
            print "Error downloading package"
            return 1
        fi
    else
        print "perl-DBD-MySQL is already at version 4.050"
        return 0
    fi
}   

# Remove cron job
remove_cron_job() {
    print "Removing cron job"
    
    # Remove the dedicated cron file
    if [ -f "/etc/cron.d/downgrade_perl_mysql" ]; then
        rm -f "/etc/cron.d/downgrade_perl_mysql"
        print "Cron job file removed"
    else
        print "Cron job file not found - may have been removed manually"
    fi
    
    return 0
}

# Main script logic
main() {
    #check if script is already running
    check_concurrency
    
    #check if rpm.lock is locked
    monitor_rpm_lock
    lock_status=$?
    
    #if rpm.lock is not locked, perform actions
    if [ $lock_status -eq 0 ]; then
        
        downgrade_perl_dbd_mysql
        action_status=$?
        
        #if actions are successful, remove cron job
        if [ $action_status -eq 0 ]; then
            remove_cron_job
            print "Script completed successfully"
        else
            print "Action execution failed, cron job not removed"
        fi
    else
        print "RPM is still locked, exiting"
    fi
    
    # Lock file removal will be handled by trap on exit
    exit 0
}

main 