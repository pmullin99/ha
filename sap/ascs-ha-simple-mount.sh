#!/bin/bash 
########################################################################## 
# title: SAP NetWeaver ENSA 1&2 HA Config Simple Mount
# author: Patrick Mullin (patrick.mullin@suse.com) Consultanting Architect
# note: <<< NO SUPPORT PROVIDED FOR THIS SCRIPT!!! >>> 
# License:      GNU General Public License 2 (GPLv2)
# Copyright (c) 2021 SUSE LLC.
# description: Automates ASCS HA settings in basic cluster
# usage:  update variables and run script on one node of cluster
########################################################################## 
## Version 1.0 Initial setup

## SAP Variables - Replace to match existing environment
# The SAP System Identification
SID=
# ASCS Instance Number
ASCS_INST=
# ERS Instance Number
ERS_INST=
# ASCS Virtual IP
ASCS_VIP=
# ERS Virtual IP
ERS_VIP=
# ASCS profile filename
ASCS_PROFILE=
# ERS profile filename
ERS_PROFILE=
# Email address for notifications
EMAIL=
# Directory for config files
CONFIG_DIR=
# Log file
LOG_FILE=

###############################################################################
## FUNCTIONS ## 
###############################################################################

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
## FUNCTION config_dir
## Purpose: Creates config directory if it dosen't exists 
###############################################################################
function config_dir() {
if [[ -d "$CONFIG_DIR" ]]
then
  MESSAGE="$CONFIG_DIR exists on your filesystem."
  show_msg "$MESSAGE"
  else
  MESSAGE="Creating $CONFIG_DIR"
  show_msg "$MESSAGE"
  mkdir -p $CONFIG_DIR
fi 
}
###############################################################################

###############################################################################
## Function set_maint_on
## Purpose:  Set cluster to maintenance mode
###############################################################################
function set_maint_on()  {
  crm configure property maintenance-mode="true"
  MESSAGE="Setting maintenance mode on cluster"
  show_msg "$MESSAGE"
}
###############################################################################

###############################################################################
## Function set_maint_off
## Purpose:  Set cluster to maintenance mode
###############################################################################
function set_maint_off()  {
  crm configure property maintenance-mode="false"
  MESSAGE="Setting maintenance mode on cluster"
  show_msg "$MESSAGE"
}
###############################################################################

###############################################################################
## Function set_ascs
## Purpose:  Setup ASCS resource group 
###############################################################################
function set_ascs()  {
  MESSAGE="Creating ASCS Group config"
  show_msg "$MESSAGE"
  cat <<EOF_ascs > ${CONFIG_DIR}/crm-ascs.txt
primitive rsc_SAPStartSrv_${SID}_ASCS${ASCS_INST} SAPStartSrv \\
  params InstanceName=${ASCS_PROFILE}

primitive rsc_SAPInstance_${SID}_ASCS${ASCS_INST} SAPInstance \\
  op monitor interval=11 timeout=60 on-fail=restart \\
  params InstanceName=${ASCS_PROFILE} \\
  START_PROFILE=/sapmnt/${SID}/profile/${ASCS_PROFILE} \\
  AUTOMATIC_RECOVER=false \\
  MINIMAL_PROBE=true \\
  meta resource-stickiness=5000 

primitive rsc_ip_${SID}_ASCS${ASCS_INST} IPaddr2 \\
  params ip=$ASCS_VIP

group grp_${SID}_ASCS${ASCS_INST} \\
  rsc_ip_${SID}_ASCS${ASCS_INST} \\
  rsc_SAPStartSrv_${SID}_ASCS${ASCS_INST} \\
  rsc_SAPInstance_${SID}_ASCS${ASCS_INST} \\
  meta resource-stickiness=3000
EOF_ascs
}
###############################################################################

###############################################################################
## Function set_ers
## Purpose:  Setup ERS Resource Group 
###############################################################################
function set_ers()  {
  MESSAGE="Creating ERS Group config"
  show_msg "$MESSAGE"
cat <<EOF_ers > ${CONFIG_DIR}/crm-ers.txt
 primitive rsc_SAPStartSrv_${SID}_ERS${ERS_INST} ocf:suse:SAPStartSrv \\
        params InstanceName=${ERS_PROFILE}

       primitive rsc_SAPInstance_${SID}_ERS${ERS_INST} SAPInstance \\
        op monitor interval=11s timeout=60s \\
        params InstanceName=${ERS_PROFILE} \\
        START_PROFILE=/sapmnt/${SID}/profile/${ERS_PROFILE} \\
        AUTOMATIC_RECOVER=false IS_ERS=true MINIMAL_PROBE=true

       primitive rsc_ip_${SID}_ERS${ERS_INST} IPaddr2 \\
        params ip=$ERS_VIP

       group grp_${SID}_ERS${ERS_INST} \\
        rsc_ip_${SID}_ERS${ERS_INST} \\
        rsc_SAPStartSrv_${SID}_ERS${ERS_INST} \\
        rsc_SAPInstance_${SID}_ERS${ERS_INST}
EOF_ers
}
###############################################################################

###############################################################################
## Function set_cs
## Purpose:  Setup Resource Constraints 
###############################################################################
function set_cs()  {
  MESSAGE="Creating Constraints config"
  show_msg "$MESSAGE"
cat <<EOF_cs > ${CONFIG_DIR}/crm-cs.txt
colocation col_${SID}_ASCS${ASCS_INST}_separate \\
  -5000: grp_${SID}_ERS${ERS_INST} grp_${SID}_ASCS${ASCS_INST}

order ord_${SID}_ASCS${ASCS_INST}_first \\
  Optional: rsc_SAPInstance_${SID}_ASCS${ASCS_INST}:start \\
  rsc_SAPInstance_${SID}_ERS${ERS_INST}:stop \\
  symmetrical=false 
EOF_cs
}
###############################################################################

###############################################################################
## Function set_mailto
## Purpose:  Setup Mailto Resource  
###############################################################################
function set_mailto()  {
  MESSAGE="Creating Mailto Resource config"
  show_msg "$MESSAGE"
cat <<EOF_mail > ${CONFIG_DIR}/crm-mail.txt
primitive mail-notify MailTo \\
        params email="${EMAIL}" \\
        op start timeout=10s interval=0 \\
        op stop timeout=10s interval=0 \\
        op monitor timeout=10s interval=10s \\
        meta target-role=Started
EOF_mail
}
###############################################################################

###############################################################################
## Function update_cluster
## Purpose:  Load Cluster Config  
###############################################################################
function update_cluster()  {
  MESSAGE="Updating cluster config"
  show_msg "$MESSAGE"
  systemctl enable sapping
  systemctl enable sappong
set_maint_on
 MESSAGE="Applying ASCS group"
 show_msg "$MESSAGE"
 crm configure load update ${CONFIG_DIR}/crm-ascs.txt
 MESSAGE="Applying ERS group"
 show_msg "$MESSAGE"
 crm configure load update ${CONFIG_DIR}/crm-ers.txt
 MESSAGE="Applying Constraints"
 show_msg "$MESSAGE"
 crm configure load update ${CONFIG_DIR}/crm-cs.txt
 MESSAGE="Applying Mailto resource"
 show_msg "$MESSAGE"
 crm configure load update ${CONFIG_DIR}/crm-mail.txt
set_maint_off
}
###############################################################################

###############################################################################
## Setup cluster - Uncomment update_cluster to apply changes to cluster
## Check $CONFIG_DIR for cluster setup files
config_dir
set_ascs
set_ers
set_cs
set_mailto
#update_cluster
