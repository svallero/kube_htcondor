# Dockerizing HTCondor master, submitter, executor nodes

FROM centos:7

MAINTAINER Sara Vallero <svallero AT to.infn.it>

EXPOSE  5000
EXPOSE  5001
EXPOSE  22

USER    root
# TODO: changeme
RUN     echo "root:pippo123" | chpasswd

# Tini (init for containers)
ENV     TINI_VERSION v0.18.0
ADD     https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /sbin/tini
RUN     chmod +x /sbin/tini

# Install packages
RUN     yum makecache fast                                         
RUN     set -ex \                                                  
        && yum -y install epel-release \                           
        && yum -y install git vim wget procps curl python-pip iproute net-tools \ 
        && yum clean all                                          

# OpenMPI Mellanox-patched
RUN     set -ex \
        && yum -y install libnl lsof numactl-libs numactl-devel ethtool gcc-c++ gcc-gfortran tcsh \
        && yum -y install make gtk2 atk cairo tcl tk perl libnl3\
        && yum clean all

COPY    MLNX_OFED_LINUX-4.5-1.0.1.0-3.10.0-957.1.3.el7.x86_64 /root/MPI_MELLANOX_4

# we assume that the RPMs are already produced                     
WORKDIR /root/MPI_MELLANOX_4/MLNX_OFED_LINUX-4.5-1.0.1.0-rhel7.6-ext
RUN     set -ex \                                                  
        && ./mlnxofedinstall --force --without-fw-update --user-space-only --hpc -q --distro rhel7

# Supervisord (process control system)
RUN     set -ex \                                                  
        && pip install supervisor supervisor-stdout                
COPY    config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf 

# SSH                                                              
RUN     set -ex \                                                  
        && yum -y install bind-utils openssh-clients openssh-server \
        && yum clean all 
COPY    config/sshd_config /etc/ssh/sshd_config  
RUN     mkdir -p /var/log/ssh      

# Install HTCondor
RUN     set -ex \
        && wget https://research.cs.wisc.edu/htcondor/yum/RPM-GPG-KEY-HTCondor \
        && rpm --import RPM-GPG-KEY-HTCondor
WORKDIR /etc/yum.repos.d
RUN     set -ex \
        && wget https://research.cs.wisc.edu/htcondor/yum/repo.d/htcondor-stable-rhel7.repo \
        && sed -i '/gpgkey=file/ a exclude=condor*' epel.repo \
        && yum -y install condor \
        && yum clean all
 

# This part is for LDAP
RUN     set -ex \                                                  
        && yum install -y openldap-clients sssd libnss-sss libpam-sss ca-certificates\
        && yum clean all                                           
COPY    scripts/ldapAuthorizedKeysCommand /sbin/ldapAuthorizedKeysCommand        
RUN mkdir -p /var/run/sshd      

# sssd daemon config                                               
COPY config/sssd.conf /etc/sssd/sssd.conf                          
RUN  chmod 600 /etc/sssd/sssd.conf                                 
COPY config/nsswitch.conf /etc/nsswitch.conf 

# for X forwarding                                                 
RUN     set -ex \
        && yum -y install xorg-x11-xauth.x86_64 \                  
        && yum clean all 

# Setup timezone                                                   
RUN rm -f /etc/localtime; ln -s  /usr/share/zoneinfo/Europe/Rome /etc/localtime  

# Condor config
COPY    config/condor_config /etc/condor/condor_config
#COPY    config/condor_mpi_reserved /etc/condor/config.d/condor_mpi_reserved
COPY    config/condor_client_auth /etc/condor/config.d/condor_client_auth

# Healthchecks
RUN     set -ex \ 
        &&  yum install -y python2-condor

RUN     set -ex \ 
        && mkdir -p /opt/health/master/ /opt/health/executor/ /opt/health/submitter/ \ 
        && pip install Flask 

COPY    healthchecks/master_healthcheck.py /opt/health/master/healthcheck.py 
COPY    healthchecks/submitter_healthcheck.py /opt/health/submitter/healthcheck.py 
COPY    healthchecks/executor_healthcheck.py /opt/health/executor/healthcheck.py 

# Publish condor queue status for elasticity
RUN     set -ex \ 
        && mkdir -p /opt/condor_status/ \ 
        && yum -y remove python-pip          
COPY    condor_status/publish_idle.py /opt/condor_status/publish_idle.py
COPY    condor_status/publish_status.py /opt/condor_status/publish_status.py





WORKDIR /
RUN useradd testuser

# entrypoint                                                       
COPY    scripts/run_centos.sh /usr/local/sbin/run.sh               
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/sbin/run.sh"]   
