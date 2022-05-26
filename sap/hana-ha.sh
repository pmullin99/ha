#!/bin/bash 
########################################################################## 
# title: HANA Performance Optimized HA Setup
# author: Patrick Mullin (patrick.mullin@suse.com) Consultanting Architect
# note: <<< NO SUPPORT PROVIDED FOR THIS SCRIPT!!! >>> 
# License:      GNU General Public License 2 (GPLv2)
# Copyright (c) 2021 SUSE LLC.
# description: Automates HANA HA configuration
# usage:  update variables and run script on one node of cluster
########################################################################## 
## Version 1.0 Initial setup

## SAP Variables - Replace to match existing environment
# The SAP System Identification

## HANA Variables - Replace SID, Instance Number, virtual IP of HANA database, email adddress for notifications and directory for config files
SID=SBX
INST_NUM=00
VIRTUAL_IP=192.168.13.17
## Directory where config files are copied
CONFIG_DIR=/root/ha
EMAIL=plm@suse.com

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
## Function set_booststrap
## Purpose:  Setup Bootstrap parameters 
###############################################################################
function set_boostrap()  {
  MESSAGE="Creating Bootstrap config"
  show_msg "$MESSAGE"
cat <<EOF_bs > ${CONFIG_DIR}/crm-bs.txt
property \$id="cib-bootstrap-options" \\
              stonith-enabled="true" \\
              stonith-action="reboot" \\
              stonith-timeout="150s"
rsc_defaults \$id="rsc-options" \\
              resource-stickiness="1000" \\
              migration-threshold="5000"
op_defaults \$id="op-options" \\
                 timeout="600"
EOF_bs
}
###############################################################################

###############################################################################
## Function set_hanatop
## Purpose:  Setup HANA Topology 
###############################################################################
function set_hanatop()  {
  MESSAGE="Creating HANA Topology config"
  show_msg "$MESSAGE"
cat <<EOF_top > ${CONFIG_DIR}/crm-saphanatop.txt
primitive rsc_SAPHanaTopology_${SID}_HDB${INST_NUM} ocf:suse:SAPHanaTopology \\
        op monitor interval="10" timeout="600" \\
        op start interval="0" timeout="600" \\
        op stop interval="0" timeout="300" \\
        params SID="${SID}" InstanceNumber="${INST_NUM}"
clone cln_SAPHanaTopology_${SID}_HDB${INST_NUM} rsc_SAPHanaTopology_${SID}_HDB${INST_NUM} \\
        meta clone-node-max="1" interleave="true"
EOF_top
}
###############################################################################

###############################################################################
## Function set_hana
## Purpose:  Setup HANA resource config 
###############################################################################
function set_hana()  {
MESSAGE="Creating HANA resource config"
show_msg "$MESSAGE"
cat <<EOF_hana > ${CONFIG_DIR}/crm-saphana.txt
primitive rsc_SAPHana_${SID}_HDB${INST_NUM} ocf:suse:SAPHana \\
        op start interval="0" timeout="3600" \\
        op stop interval="0" timeout="3600" \\
        op promote interval="0" timeout="3600" \\
        op monitor interval="60" role="Master" timeout="700" \\
        op monitor interval="61" role="Slave" timeout="700" \\
        params SID="${SID}" InstanceNumber="${INST_NUM}" PREFER_SITE_TAKEOVER="true" \\
        DUPLICATE_PRIMARY_TIMEOUT="7200" AUTOMATED_REGISTER="True"
ms msl_SAPHana_${SID}_HDB${INST_NUM} rsc_SAPHana_${SID}_HDB${INST_NUM} \\
        meta clone-max="2" clone-node-max="1" interleave="true"
EOF_hana
}
###############################################################################

###############################################################################
## Function set_vip
## Purpose:  Setup Virtual IP resource config 
###############################################################################
function set_vip()  {
MESSAGE="Creating Virtual IP resource config"
show_msg "$MESSAGE"
cat <<EOF_vip > ${CONFIG_DIR}/crm-vip.txt
primitive rsc_ip_${SID}_HDB${INST_NUM} ocf:heartbeat:IPaddr2 \\
        op monitor interval="10s" timeout="20s" \\
        params ip="$VIRTUAL_IP"
EOF_vip
}
###############################################################################

###############################################################################
## Function set_cs
## Purpose:  Setup Constraints config 
###############################################################################
function set_cs()  {
MESSAGE="Creating Contraints config"
show_msg "$MESSAGE"
cat <<EOF_cs > ${CONFIG_DIR}/crm-cs.txt
colocation col_saphana_ip_${SID}_HDB${INST_NUM} 2000: rsc_ip_${SID}_HDB${INST_NUM}:Started \\
    msl_SAPHana_${SID}_HDB${INST_NUM}:Master
order ord_SAPHana_${SID}_HDB${INST_NUM} Optional: cln_SAPHanaTopology_${SID}_HDB${INST_NUM} \\
    msl_SAPHana_${SID}_HDB${INST_NUM}
EOF_cs
}
###############################################################################

###############################################################################
## Function set_mail
## Purpose:  Setup Mailto config 
###############################################################################
function set_mail()  {
MESSAGE="Creating MailTo resource config"
show_msg "$MESSAGE"  
cat <<EOF_mail > ${CONFIG_DIR}/crm-mail.txt
primitive email-notify MailTo \\
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
  set_maint_on
  MESSAGE="Applying Booststrap"
  show_msg "$MESSAGE"
  crm configure load update ${CONFIG_DIR}/crm-bs.txt 
  MESSAGE="Applying HANA Topology"
  show_msg "$MESSAGE"
  crm configure load update ${CONFIG_DIR}/crm-saphanatop.txt
  MESSAGE="Applying HANA Resource"
  show_msg "$MESSAGE"
  crm configure load update ${CONFIG_DIR}/crm-saphana.txt
  MESSAGE="Applying Virtual IP"
  show_msg "$MESSAGE"
  crm configure load update ${CONFIG_DIR}/crm-vip.txt
  MESSAGE="Applying Constraints"
  show_msg "$MESSAGE"
  crm configure load update ${CONFIG_DIR}/crm-cs.txt
  MESSAGE="Applying Mailto resource"
  show_msg "$MESSAGE"
  crm configure load update ${CONFIG_DIR}/crm-mail.txt
set_maint_off
}
###############################################################################
config_dir
set_boostrap
set_hanatop
set_hana
set_vip
set_cs
set_mail
update_cluster






