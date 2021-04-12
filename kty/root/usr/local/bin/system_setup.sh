#!/bin/bash

logfile="/var/log/k3s-install.log"

echo "Start to initialize the system" 2>&1 | tee -a $logfile
echo `date +"%x %X"` 2>&1 | tee -a $logfile

echo "Check if there are two active network interfaces"
IF0=''
IF1=''
for IFTEMP in `ls /sys/class/net/ | grep -v "\`ls /sys/devices/virtual/net/\`"`; do
    if [ $IFTEMP == 'lo' ]; then
        continue
    fi
    echo "Try to check the interface: $IFTEMP" | tee -a $logfile
    ip link set $IFTEMP up
    IFUP=`cat /sys/class/net/$IFTEMP/operstate`
    if [ $IFUP == 'up' ]; then
        if [ -z $IF0 ]; then
             IF0=$IFTEMP
             continue
        fi
        IF1=$IFTEMP
    fi
    if [ -z $IF1 ]; then
         break   
    fi
done

if [ -z $IF1 ]; then
    echo "ERROR: there is no two active network interfaces" 2>&1 | tee -a $logfile
    exit 1
fi

echo "There are two active network interfaces: $IF0 $IF1" 2>&1 | tee -a $logfile


echo "Settingg hostname" 2>&1 | tee -a $logfile
HOSTNAME='node'
echo -n "Input the hostname (default: node): "
read -r
name="${REPLY:-$HOSTNAME}"

echo "Setting networking" 2>&1 | tee -a $logfile
IF0_ADDR=''
echo -n "Input the ip address and netmask for $IF0 (e.g: 192.168.100.10/24) : "
read -r
IF0_ADDR=$REPLY
if [ -z $IF0_ADDR ]; then
    echo "ERROR: ip address of $IF0 is NULL"  2>&1 | tee -a $logfile
    exit 1
fi

#IF0_NETMASK='255.255.255.0'
#echo -n "Input the netmask for $IF0 (default: 255.255.255.0): "
#read -r
#IFO_NETMASK="${REPLY:-$IF0_NETMASK}"
#if [ -z $IF0_NETMASK ]; then
#    echo "ERROR: netmastk of $IF0 is NULL"  2>&1 | tee -a $logfile
#    exit 1
#fi

IF1_ADDR=''
echo -n "Input the ip address and netmask for $IF1 (e.g: 192.168.100.11/24) : "
read -r
IF1_ADDR=$REPLY
if [ -z $IF1_ADDR ]; then
    echo "ERROR: ip address of $IF1 is NULL"  2>&1 | tee -a $logfile
    exit 1
fi

#IF1_NETMASK='255.255.255.0'
#echo -n "Input the netmask for $IF1 (default: 255.255.255.0): "
#read -r
#IFO_NETMASK="${REPLY:-$IF1_NETMASK}"
#if [ -z $IF1_NETMASK ]; then
#    echo "ERROR: netmastk of $IF1 is NULL"  2>&1 | tee -a $logfile
#   exit 1
#fi

GW_DEFAULT=''
echo -n "Input the default gateway (e.g: 192.168.100.254): "
read -r
GW_DEFAULT=$REPLY

echo "--------------------------------------"
echo "Hostname: $HOSTNAME" 2>&1 | tee -a $logfile
echo "ip address of $IF0: $IF0_ADDR" 2>&1 | tee -a $logfile
#echo "netmastk of $IFO: $IF0_NETMASK" 2>&1 | tee -a $logfile
echo "ip address of $IF1: $IF1_ADDR" 2>&1 | tee -a $logfile
#echo "netmastk of $IF1: $IF1_NETMASK" 2>&1 | tee -a $logfile
echo "default gateway: $GW_DEFAULT" 2>&1 | tee -a $logfile
echo "-------------------------------------"

CONFIRM='yes'
echo -n "Confirm the above network setting (yes/no, defaut:yes): "
read -r
CONFIRM="${REPLY:-$CONFIRM}"
if [ "$CONFIRM" != 'yes' ]; then
    echo "ERROR: the setting is not confirmed, please retry again!" 2>&1 | tee -a $logfile
    exit 1
fi

echo "Starting to set the networking ..." 2>&1 | tee -a $logfile
hostname "$HOSTNAME"
echo "$HOSTNAME" > /etc/hostname

echo "check the ip setting is successful" 2>&1 | tee -a $logfile
ip addr add $IF0_ADDR dev $IF0 2>&1 | tee -a $logfile
if [ $? == 1 ]; then
    echo "ERROR: fail to set the ip address of IF0: $IF0_ADDR" 2>&1 | tee -a $logfile
    exit 1
fi

ip addr add $IF1_ADDR dev $IF1 2>&1 | tee -a $logfile
if [ $? == 1 ]; then
    echo "ERROR: fail to set the ip address of IF1: $IF1_ADDR" 2>&1 | tee -a $logfile
    exit 1
fi

if [ -n $GW_DEFAULT ]; then
    ip route del default
    ip route add default via $GW_DEFAULT
    if [ $? == 1 ]; then
        echo "ERROR: fail to set the default gateway: $GW_DEFAULT" 2>&1 | tee -a $logfile
        exit 1
    fi
fi

cat >/etc/sysconfig/network/ifcfg-$IF0 <<EOF
BOOTPROTO='static'
MTU=''
REMOTE_IPADDR=''
STARTMODE='auto'
IPADDR='$IF0_ADDR'
EOF


cat >/etc/sysconfig/network/ifcfg-$IF1 <<EOF
BOOTPROTO='static'
MTU=''
REMOTE_IPADDR=''
STARTMODE='auto'
IPADDR='$IF1_ADDR'
EOF

cat >/etc/sysconfig/network/routes <<EOF
default $GW_DEFAULT - -
EOF

systemctl restart network

echo "Success to set the networking" 2>&1 | tee -a $logfile

echo "set hosts" 2>&1 | tee -a $logfile

sed -i '/\ '${HOSTNAME}'/d' /etc/hosts

APP_IP=`ip -4 a show ${IF1} | grep inet | awk '{ print $2 }' | awk -F "/" '{print $1}'`
echo "${APP_IP} ${HOSTNAME}" >> /etc/hosts

echo "Startup Docker" 2>&1 | tee -a $logfile

systemctl restart docker && systemctl enable docker 


echo "Setup K3S and Rancher"
cd /k3s-rancher-oneclick/k3s-install/
./k3s-install.sh

echo "Setup the application"
cd /k3s-rancher-oneclick/centerdeploy/
./restoredata.sh

exit 0



