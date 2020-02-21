#!/bin/bash
# Configure HTCondor and fire up supervisord
# Daemons for each role
MASTER_DAEMONS="COLLECTOR, NEGOTIATOR"
EXECUTOR_DAEMONS="STARTD"
SUBMITTER_DAEMONS="SCHEDD"

usage() {
  cat <<-EOF
	usage: $0 -m|-e master-address|-s master-address [-c url-to-config] [-r url-to-public-key] [-i user id] [-l ldap] [-k url-to-public-key] [-n url-to-private-key] [-p password] [-u inject user] [-S shared-secret] -C [mpi cores] -D [dedicated scheduer]
	
	Configure HTCondor role and start supervisord for this container. 
	
	OPTIONS:
	  -m                	   configure container as HTCondor master
	  -e   master-address 	   configure container as HTCondor executor for the given master
	  -s   master-address 	   configure container as HTCondor submitter for the given master
	  -c   url-to-config  	   config file reference from http url
	  -r   url-to-public-key   url to public key for ssh access to root
	  -i   user id		   user password (see -u attribute)
          -l   ldap                configure ldap 
	  -k   url-to-public-key   url to public key for ssh access to unprivileged user (see -u attribute)
	  -n   url-to-private-key  url to private key for ssh access to unprivileged user (passwordless unprivileged login among cluster, useful for MPI)
	  -p   password		   user password (see -u attribute)
	  -u   inject user	   inject a user without root privileges for submitting jobs accessing via ssh. -k public key required -p  password optional -i user id optional
          -S                       shared secret
          -C                       number of cpus to configure partitionable slots for mpi
          -D                       name of dedicated scheduler (needed if -C option is specified)
	EOF
  exit 1
}

# Syntax checks
CONFIG_MODE=
# Default value assigned by SV for testing
SSH_ACCESS='yes'
#SSH_ACCESS=

# Get our options
ROLE_DAEMONS=
CONDOR_HOST=
HEALTH_CHECK=
CONFIG_URL=
KEY_URL=
USER_KEY_URL=
USER_PRIV_KEY_URL=
USER=
USER_ID=
PASSWORD=
LDAP=
while getopts ':me:s:c:r:i:l:k:n:p:u:S:C:D:' OPTION; do
  case $OPTION in
    m)
      [ -n "$ROLE_DAEMONS" ] && usage
      ROLE_DAEMONS="$MASTER_DAEMONS"
      #CONDOR_HOST='$(FULL_HOSTNAME)'
      CONDOR_HOST='$(IP_ADDRESS)'
      HEALTH_CHECK='master'
    ;;
    e)
      [ -n "$ROLE_DAEMONS" -o -z "$OPTARG" ] && usage
      ROLE_DAEMONS="$EXECUTOR_DAEMONS"
      CONDOR_HOST="$OPTARG"
      HEALTH_CHECK='executor'
    ;;
    c)
      [ -n "$CONFIG_MODE" -o -z "$OPTARG" ] && usage
      CONFIG_MODE='http'
      CONFIG_URL="$OPTARG"
    ;;
    s)
      [ -n "$ROLE_DAEMONS" -o -z "$OPTARG" ] && usage
      ROLE_DAEMONS="$SUBMITTER_DAEMONS"
      CONDOR_HOST="$OPTARG"
      HEALTH_CHECK='submitter'
    ;;
    r)
      [ -n "$KEY_URL" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      KEY_URL="$OPTARG"
    ;;  
    i)
      [ -n "$USER_ID" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      USER_ID="$OPTARG"
    ;;  
    l)
      [ -n "$LDAP" -o -z "$OPTARG" ] && usage
      LDAP="$OPTARG"
    ;;  
    k)
      [ -n "$USER_KEY_URL" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      USER_KEY_URL="$OPTARG"
    ;;  
    n)
      [ -n "$USER_PRIV_KEY_URL" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      USER_PRIV_KEY_URL="$OPTARG"
    ;;  
    p)
      [ -n "$PASSWORD" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      PASSWORD="$OPTARG"
    ;;  
    u)
      [ -n "$USER" -o -z "$OPTARG" ] && usage
      SSH_ACCESS='yes'
      USER="$OPTARG"
    ;;  
    S)
      [ -n "$SHARED_SECRET" -o -z "$OPTARG" ] && usage
      SHARED_SECRET="$OPTARG"
    ;; 
    C)
      [ -n "$MPI_SLOTS" -o -z "$OPTARG" ] && usage
      MPI_SLOTS="$OPTARG"
    ;;  
    D)
      [ -n "$DEDICATED_SCHEDULER" -o -z "$OPTARG" ] && usage
      DEDICATED_SCHEDULER="$OPTARG"
    ;;  
    *)
      usage 
    ;;
  esac
done

# USER KEY IS REQUIRED
if [ \( -n "$USER_KEY_URL" -a -z "$USER" \) -a \( -z "$USER_KEY_URL" -a -n "$USER" \) ]; then
  usage
fi;

# Prepare SSH access
if [ -n "$KEY_URL" -a -n "$SSH_ACCESS" ]; then
  wget -O - "$KEY_URL" --no-check-certificate > /root/.ssh/authorized_keys
fi

# USER_KEY_URL can be an array with parameters
if [ -n "$USER" -a -n "$USER_KEY_URL" -a -n "$SSH_ACCESS" ]; then
  mkdir -p /home/$USER 
  # fix user id, useful when mounting volumes (optional)
  if [ -n "$USER_ID" ]; then  
     useradd $USER -u $USER_ID -d /home/$USER -s /bin/bash 
  else
     useradd $USER -d /home/$USER -s /bin/bash 
  fi;
  chown -R $USER:$USER /home/$USER/
  mkdir -p /home/$USER/.ssh 
  chmod 700 /home/$USER/.ssh
  # do not check hosts
  config="/home/$USER/.ssh/config"
  if ! grep -q '# Written by marathon' $config; then
  cat >> $config << _EOF_
# Written by marathon
Host 192.168.*
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null

Host occam-00.ph.unito.it
 RSAAuthentication yes
 IdentityFile ~/.ssh/<changeme>
_EOF_
  chmod 644 $config 
fi
  # public key
  IFS=' ' read -a A_USER_KEY_URL <<<"${USER_KEY_URL}"
  wget -O - "${A_USER_KEY_URL[@]}" > /home/$USER/.ssh/authorized_keys 
  chmod 600 /home/$USER/.ssh/authorized_keys
  # private key (optional)
  if [ -n "$USER_PRIV_KEY_URL" ]; then
      IFS=' ' read -a A_USER_PRIV_KEY_URL <<<"${USER_PRIV_KEY_URL}"   
      wget -O - "${A_USER_PRIV_KEY_URL[@]}" > /home/$USER/.ssh/id_rsa 
      chmod 400 /home/$USER/.ssh/id_rsa
  fi;
  chown -R $USER:$USER /home/$USER/.ssh
fi;

if [ -n "$USER" -a -n "$PASSWORD" -a -n "$SSH_ACCESS" ]; then
  echo "$USER:$PASSWORD" | chpasswd 
fi;

if [ -n "$SSH_ACCESS" ]; then

  #ssh-keygen -b 1024 -t rsa -f /etc/ssh/ssh_host_key
  #ssh-keygen -b 1024 -t rsa -f /etc/ssh/ssh_host_rsa_key
  #ssh-keygen -b 1024 -t dsa -f /etc/ssh/ssh_host_dsa_key
  ssh-keygen -f /etc/ssh/ssh_host_rsa_key -N '' -t rsa
  ssh-keygen -f /etc/ssh/ssh_host_ecdsa_key -N '' -t ecdsa
  ssh-keygen -f /etc/ssh/ssh_host_ed25519_key -N '' -t ed25519
  cat >> /etc/supervisor/conf.d/supervisord.conf << EOL

[program:sshd]
command=/usr/sbin/sshd -D
autostart=true
stdout_logfile=/var/log/ssh/sshd.stdout.log
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=10
stderr_logfile=/var/log/ssh/sshd.stderr.log
stderr_logfile_maxbytes=1MB
stderr_logfile_backups=10
EOL

fi;

# Prepare external config
if [ -n "$CONFIG_MODE" ]; then
  wget -O - "$CONFIG_URL" > /etc/condor/condor_config
fi

# Prepare HTCondor configuration
sed -i \
  -e 's/@CONDOR_HOST@/'"$CONDOR_HOST"'/' \
  -e 's/@ROLE_DAEMONS@/'"$ROLE_DAEMONS"'/' \
  /etc/condor/condor_config

if [[ $ROLE_DAEMONS == *"COLLECTOR"* ]]; then 
  echo "COLLECTOR_HOST=$CONDOR_HOST" >> /etc/condor/condor_config
fi
 
# Add shared secret to HTCondor configuration
if [ -n "$SHARED_SECRET" ]; then
  
  cat >> /etc/condor/condor_config << _EOF_
SEC_PASSWORD_FILE= /etc/condor/condorSharedSecret
SEC_DAEMON_INTEGRITY= REQUIRED
SEC_DAEMON_AUTHENTICATION= REQUIRED
SEC_DAEMON_AUTHENTICATION_METHODS= PASSWORD
_EOF_
 
  condor_store_cred -f /etc/condor/condorSharedSecret -p $SHARED_SECRET
fi

# We need to use ip addresses in condor contact file
#sed -i 's/hostname=`hostname`/hostname=`hostname -I`/g' /usr/libexec/condor/sshd.sh

# Configure partitionable slots for MPI
if [ -n "$MPI_SLOTS" ]; then
  echo "MPI_SLOTS: $MPI_SLOTS"
  echo "DEDICATED SCHEDULER: $DEDICATED_SCHEDULER"
  if [ -z "$DEDICATED_SCHEDULER" ]; then 
      usage
  fi
IP=`ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -f1 -d'/'`

  cat >> /etc/condor/config.d/condor_config_mpi << _EOF_
# MPI partitions
SLOT_TYPE_1_PARTITIONABLE = True
SLOT_TYPE_1 = CPUS=$MPI_SLOTS
NUM_SLOTS_TYPE_1 = 1
# Dedicated Scheduler
DedicatedScheduler = "DedicatedScheduler@$DEDICATED_SCHEDULER"
STARTD_ATTRS = \$(STARTD_ATTRS) DedicatedScheduler
RANK = Scheduler =?= \$(DedicatedScheduler)

# SSH connection required by MPI jobs
CONDOR_SSHD = /usr/sbin/sshd
CONDOR_SSH_KEYGEN = /usr/bin/ssh-keygen

# Do not use DNS (container names are not resolved by kube)
#NETWORK_INTERFACE = $IP
#NO_DNS = True
#DEFAULT_DOMAIN_NAME = executor
_EOF_
fi  

# Allow administrators
if [ -n "$USER" ]; then
  
  cat >> /etc/condor/condor_config << _EOF_
# CONDOR_ADMIN = $USER@$USER-submitter.marathon.occam-mesos, root@*
CONDOR_ADMIN = $USER@*, root@*
QUEUE_SUPER_USERS = root, condor, $USER
_EOF_

fi 

# Prepare right HTCondor healthchecks
sed -i \
  -e 's/@ROLE@/'"$HEALTH_CHECK"'/' \
  /etc/supervisor/conf.d/supervisord.conf

# Publish queue status if role is submitter
if [ $HEALTH_CHECK == "submitter" ]; then 
  cat >> /etc/supervisor/conf.d/supervisord.conf << _EOF_

[program:publish_queue]
command=python /opt/condor_status/publish_status.py
stderr_logfile=/var/log/condor_status.err
autostart=true
_EOF_
fi 

# Colorful user prompt 
if [ -n "$USER" ]; then

#  cat >> /home/$USER/.bash_profile << _EOF_ 
#export PS1="\[\033[38;5;13m\]\u\[$(tput sgr0)\]\[\033[38;5;14m\]@\h\\$\[$(tput sgr0)\]\[\033[38;5;15m\]\[$(tput sgr0)\]"
#_EOF_

echo 'export PS1="\[\033[38;5;201m\]\u\[$(tput sgr0)\]\[\033[38;5;34m\]@\[$(tput sgr0)\]\[\033[38;5;46m\]\h\[$(tput sgr0)\]\[\033[38;5;34m\]$\[$(tput sgr0)\]\[\033[38;5;15m\] \[$(tput sgr0)\]"' >> /home/$USER/.bash_profile 
 
chown $USER:$USER /home/$USER/.bash_profile
fi

# create a dummy eth0 interface for intel compiler's hostid
#ip link add name dummy0 type dummy
#ip link set name eth0 dev dummy0
#ifconfig eth0 hw ether ee:ee:ee:ee:ee:ee

#ip link add name dummy1 type dummy
#ip link set name eth1 dev dummy1
#ifconfig eth1 hw ether 00:0a:f7:96:cd:ca

# deny access to nodes
if [[ $HEALTH_CHECK == "executor" ]]; then 
echo "" >> /etc/ssh/sshd_config
echo "Match User *,!root" >> /etc/ssh/sshd_config
echo "    ForceCommand echo \"You are not authorized to login to this node.\"" >> /etc/ssh/sshd_config
fi

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
