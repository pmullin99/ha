#!/bin/bash 
########################################################################## 
# title: Join Basic Cluster Setup
# author: Patrick Mullin (patrick.mullin@suse.com) Consultanting Architect
# note: <<< NO SUPPORT PROVIDED FOR THIS SCRIPT!!! >>> 
# License:      GNU General Public License 2 (GPLv2)
# Copyright (c) 2021 SUSE LLC.
# description: Automates joining a basic cluster
# usage:  update variables and run script on joining node of cluster
########################################################################## 
## Version 1.0 Initial setup

## SAP SYSTEM ID
SID=SBX
## Set if this will be a HANA or APPSERVER
SAP=HANA
#SAP=APPSERVER
## Enter the appropriate watchdog for your environment
WATCHDOG=softdog
LOG_FILE=/var/log/basic-cluster-setup.log
## SBD disks.  Use the /dev/disk/by-id/<disk> name.
SBD_DISK1=/dev/disk/by-id/scsi-36001405f0952e9730ed4ed3b0e1e80c2
SBD_DISK2=/dev/disk/by-id/scsi-36001405f0952e9730ed4ed3b0e1e80c3
SBD_DISK3=/dev/disk/by-id/scsi-36001405f0952e9730ed4ed3b0e1e80c4
## Network interfaced used for corosync heartbeat
INTERFACE=eth0
## IP address or hostname of existing cluster node
CLUSTER_IP=192.168.13.11

###############################################################################
## FUNCTION show_msg
## Purpose: Format messages 
###############################################################################
function show_msg() {
  TS=$(date +%m"-"%d-%H:%M:%S)
  MSG=$1
  echo "${TS}: ${MSG}" | tee -a $LOG_FILE
}
###############################################################################

###############################################################################
## FUNCTION install_ha
## Purpose: Install ha packages 
###############################################################################
function install_ha() {
  MESSAGE="Installing HA and SAP packages"
  show_msg "$MESSAGE"
  zypper --non-interactive in -t pattern ha_sles
  if [ "$SAP" == "HANA" ]; then
    zypper --non-interactive in SAPHanaSR SAPHanaSR-doc supportutils-plugin-ha-sap saptune
   else
    zypper --non-interactive in sap-suse-cluster-connector sapstartsrv-resource-agents supportutils-plugin-ha-sap saptune
  fi
}
###############################################################################

###############################################################################
## FUNCTION saptune_setup
## Purpose: Setup Saptune 
###############################################################################
function saptune_setup() {
  if [ "$SAP" == "HANA" ]; then
   MESSAGE="Setup saptune for solution S4HANA-DBSERVER:"
   show_msg "$MESSAGE"
   saptune solution apply S4HANA-DBSERVER
   MESSAGE="Verifying saptune solution S4HANA-DBSERVER"
   show_msg "$MESSAGE"
   MESSAGE=$(saptune solution verify S4HANA-DBSERVER)
   show_msg "$MESSAGE"
  else
   MESSAGE="Setup saptune for solution S4HANA-APPSERVER:"
   show_msg "$MESSAGE"
   saptune solution apply S4HANA-APPSERVER
   MESSAGE="Verifying saptune solution S4HANA-APPSERVER"
   show_msg "$MESSAGE"
   MESSAGE=$(saptune solution verify S4HANA-APPSERVER)
   show_msg "$MESSAGE"
  fi
}
###############################################################################

###############################################################################
## FUNCTION watchdog_setup
## Purpose: Setup Watchdog (adjust watchdog per environment) 
###############################################################################
function watchdog_setup() {
 MESSAGE="Setup watchdog $WATCHDOG"
    show_msg "$MESSAGE"
 modprobe $WATCHDOG
 echo "$WATCHDOG" > /etc/modules-load.d/watchdog.conf
 systemctl restart systemd-modules-load
 MESSAGE="watchdog is now configured and running:"
 show_msg "$MESSAGE"
 MESSAGE=$(lsmod |grep dog)
 show_msg "$MESSAGE"
}
###############################################################################

###############################################################################
## FUNCTION check_chrony
## Purpose: Check if chrony is running 
###############################################################################
function check_chrony() {
  SERVICE=$(systemctl is-active chronyd)
  if [ "$SERVICE" == "inactive" ]; then
   MESSAGE="chronyd is not running:"
   show_msg "$MESSAGE"
   MESSAGE="Activating chronyd - Check Chronyd config"
   show_msg "$MESSAGE"
   systemctl enable --now chronyd
  else
   MESSAGE="Chronyd is running"
   show_msg "$MESSAGE"
  fi
}
###############################################################################

###############################################################################
## FUNCTION sbd_timeout
## Purpose: Adjust sbd timeout values 
###############################################################################
function sbd_timeout() {
    MESSAGE="Adjust sbd timeouts"
    show_msg "$MESSAGE"
    cp /usr/lib/systemd/system/sbd.service /etc/systemd/system/sbd.service
    sed -i '/^RefuseManualStart*/a Before=corosync.service' /etc/systemd/system/sbd.service
    sed -i 's/^# TimeoutSec=/TimeoutSec=600/g' /etc/systemd/system/sbd.service
    systemctl daemon-reload
}
###############################################################################

###############################################################################
## FUNCTION cluster_join
## Purpose: initialize cluster 
###############################################################################
function cluster_join() {
    MESSAGE="Joining cluster node, you will be prompted for password if ssh keys are not set"
    show_msg "$MESSAGE"
    crm cluster join -y -i $INTERFACE -c $CLUSTER_IP 
    wait
    #SIDADM=$(echo ${SID}adm | tr '[:lower:]')
    #usermod -aG haclient $SIDADM
    MESSAGE=$(crm_mon -1)
    show_msg "$MESSAGE"
    systemctl enable pacemaker 
}
###############################################################################

## Setup HA
install_ha
#saptune_setup
watchdog_setup
check_chrony
#sbd_timeout
cluster_join
