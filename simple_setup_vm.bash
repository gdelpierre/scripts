#! /usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o posix

#trap delete_me EXIT

usage() 
{
	cat << EOF

Usage: $0 [options] ARGS

Options:
  -h    Set hostname
  -4    Set IPv4
  -6    Set IPv6
  -?    Display usage

Examples:

$0 -h server-name-01 -4 141.138.XX.XXX/24 -6 2a01:a580:6:XXXX:XXX

EOF
exit 0
}

[[ $# -lt 1 ]] && usage

ERR=
IPV4=
IPV6=
VOL=

# Catching arguments passed
while getopts ":h:4:6:?" OPTS ; do
	case $OPTS in
		h)
			HOST=${OPTARG}
			;;
		4)
			IPV4=${OPTARG}
			;;
		6)
			IPV6=${OPTARG}
			;;
		?)
			usage
			;;
		\?)
			echo "Invalid options: -$OPTARG" >&2
			usage
			;;
	esac
done

# Controls
[[ -z "$HOST" ]] &&
echo "ERROR : Please provide a hostname" &&
usage

[[ -z "$IPV4" ]] && ERR=${ERR:-4} || [[ -z "$IPV6" ]] && ERR=${ERR:-6} &&
{
	echo "ERROR: Please provide an IPv$ERR address" ;
	usage ;
}

[[ "$IPV4" == *"/"* ]] ||
{
	echo "ERROR: no CIDR found in IPv4" ; 
	usage ; 
}

# IPv{4,6} assignation.
NETMASK=$(ipcalc -b -n $IPV4 | awk '/Netmask/ {print $2}')
GATEWAY=$(ipcalc -b -n $IPV4 | awk '/HostMin/ {print $2}')
BROADCAST=$(ipcalc -b -n $IPV4 | awk '/Broadcast/ {print $2}')
NETWORK=$(ipcalc -b -n $IPV4 | awk '/Network/ {gsub(/\/.*/,"") ; print $2}')
GATEWAY6="${IPV6%::*}::1"
IPV4=${IPV4%%\/*}

# Files to modify
files_with_hostname="/etc/mailname /etc/postfix/main.cf /etc/hostname /etc/hosts /var/cache/debconf/config.dat" 
files_with_ip="/etc/hosts /etc/network/interfaces"

delete_me()
{
	rm -- $0
}

detect_if_sdb_exists()
{
	[[ -b /dev/sdb ]] && [[ ! -b /dev/sdb1 ]] &&
	! grep -qs "/dev/sdb" /proc/mounts &&
	mkfs.xfs /dev/sdb ||
	{
		VOL="false" ;
		printf "/dev/sdb not found ; continue\n" ;
	}
}

populate_fstab()
{
	local UUID=$(blkid -s UUID -o value /dev/sdb)
	printf "# /srv\nUUID=$UUID\t/srv\txfs\tnoatime,nodiratime,logbufs=8\t0\t2\n" >> /etc/fstab
}

set_network_config()
{
	cat << EOF > /etc/network/interfaces
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet static
	address		$IPV4
	netmask		$NETMASK
	network		$NETWORK
	broadcast	$BROADCAST
	gateway		$GATEWAY

auto eth0
iface eth0 inet6 static
	address		$IPV6
	netmask		64
	gateway		$GATEWAY6
EOF
}

regen_ssh_keys()
{
	rm /etc/ssh/*_key{,\.pub}
	dpkg-reconfigure openssh-server
}

# set new hostname
hostname "$HOST"

# replace hostname where it is set
sed -i -e "s/immadatemplate/$HOST/g" $files_with_hostname

# Configure the second volume.
detect_if_sdb_exists
[[ -z ${VOL} ]] && populate_fstab

# Configure networking.
set_network_config
regen_ssh_keys

# regen aliases
newaliases

exit 0
