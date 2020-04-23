#!/bin/bash

# arguments are zero based
if [ "$#" -eq 0 ]; then
    echo "Illegal number of parameters - we expect the base path here"
    exit 0
fi

export CHROOT=$1

echo "running user script in $CHROOT"

echo "Box create at: " >$CHROOT/branded-vm
date >>$CHROOT/branded-vm

KEXTPOLICY_FILE="${CHROOT}/private/var/db/SystemPolicyConfiguration/KextPolicy"

# we only need this when testing the script
mkdir -p "${CHROOT}/private/var/db/SystemPolicyConfiguration"

if [  ! -f $KEXTPOLICY_FILE ]; then
    echo "Creating KextPolicy database"
    /usr/bin/sqlite3 ${KEXTPOLICY_FILE} <<EOF
            PRAGMA foreign_keys=OFF;
            BEGIN TRANSACTION;
            CREATE TABLE kext_load_history_v3 ( path TEXT PRIMARY KEY, team_id TEXT, bundle_id TEXT, boot_uuid TEXT, created_at TEXT, last_seen TEXT, flags INTEGER );
            CREATE TABLE kext_policy ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, developer_name TEXT, flags INTEGER, PRIMARY KEY (team_id, bundle_id) );
            CREATE TABLE kext_policy_mdm ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, payload_uuid TEXT, PRIMARY KEY (team_id, bundle_id) );
            CREATE TABLE settings ( name TEXT, value TEXT, PRIMARY KEY (name) );
            COMMIT;
EOF
fi

echo "Whitelisting KextPolicy"

/usr/bin/sqlite3 ${KEXTPOLICY_FILE} <<EOF
        BEGIN TRANSACTION;
        INSERT OR REPLACE INTO kext_policy VALUES('VB5E2TV963','org.virtualbox.kext.VBoxDrv',1,'Oracle America, Inc.',1);
        INSERT OR REPLACE INTO kext_policy VALUES('VB5E2TV963','org.virtualbox.kext.VBoxUSB',1,'Oracle America, Inc.',1);
        INSERT OR REPLACE INTO kext_policy VALUES('VB5E2TV963','org.virtualbox.kext.VBoxNetFlt',1,'Oracle America, Inc.',1);
        INSERT OR REPLACE INTO kext_policy VALUES('VB5E2TV963','org.virtualbox.kext.VBoxNetAdp',1,'Oracle America, Inc.',1);

        INSERT OR REPLACE INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.VMwareGfx',1,'VMware, Inc.',1);
        INSERT OR REPLACE INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmmemctl',1,'VMware, Inc.',1);
        INSERT OR REPLACE INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmhgfs',1,'VMware, Inc.',1);
        COMMIT;
EOF

echo "Disable Login screensaver"

# https://www.macobserver.com/tips/disable-os-x-login-screen-saver/
defaults write ${CHROOT}/Library/Preferences/com.apple.screensaver loginWindowIdleTime 0
