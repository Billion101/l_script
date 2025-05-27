#!/bin/bash

set -e

echo "Step 1: Update system and install BIND9"
sudo apt update && sudo apt upgrade -y
sudo apt install -y bind9utils dnsutils ufw net-tools

echo "Step 2: Set static IP address"
sudo bash -c 'cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.10.22/24]
      gateway4: 192.168.10.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF'

sudo netplan apply

echo "Step 3: Set hostname and /etc/hosts"
sudo hostnamectl set-hostname ns.kham.site
sudo bash -c 'cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ns.kham.site

192.168.10.22 ns.kham.site ns
EOF'

echo "Step 4: Configure named.conf.options"
sudo bash -c 'cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";

    recursion yes;
    allow-query { any; };
    listen-on { 127.0.0.1; 192.168.10.22; };
    allow-recursion { 192.168.10.0/24; };

    forwarders {
        8.8.8.8;
        1.1.1.1;
    };

    dnssec-validation auto;
};
EOF'

echo "Step 5: Configure zones in named.conf.local"
sudo bash -c 'cat > /etc/bind/named.conf.local <<EOF
zone "kham.site" {
    type master;
    file "/etc/bind/db.kham.site";
};

zone "kham.com" {
    type master;
    file "/etc/bind/db.kham.com";
};

zone "10.168.192.in-addr.arpa" {
    type master;
    file "/etc/bind/db.192.168.10";
};
EOF'

echo "Step 6: Create forward zone file for kham.site"
sudo cp /etc/bind/db.local /etc/bind/db.kham.site
sudo bash -c 'cat > /etc/bind/db.kham.site <<EOF
\$TTL    604800
@       IN      SOA     ns.kham.site. admin.kham.site. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.kham.site.
@       IN      MX 10   mail.kham.site.
@       IN      A       192.168.10.22
ns      IN      A       192.168.10.22
mail    IN      A       192.168.10.10
www     IN      A       192.168.10.30
EOF'

echo "Step 7: Create forward zone file for kham.com"
sudo cp /etc/bind/db.local /etc/bind/db.kham.com
sudo bash -c 'cat > /etc/bind/db.kham.com <<EOF
\$TTL    604800
@       IN      SOA     ns.kham.site. admin.kham.site. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.kham.site.
@       IN      MX 10   mail.kham.com.
@       IN      A       192.168.10.22
ns      IN      A       192.168.10.22
mail    IN      A       192.168.10.11
www     IN      A       192.168.10.31
EOF'

echo "Step 8: Create reverse zone file"
sudo cp /etc/bind/db.127 /etc/bind/db.192.168.10
sudo bash -c 'cat > /etc/bind/db.192.168.10 <<EOF
\$TTL    604800
@       IN      SOA     ns.kham.site. admin.kham.site. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.kham.site.
22      IN      PTR     ns.kham.site.
10      IN      PTR     mail.kham.site.
11      IN      PTR     mail.kham.com.
30      IN      PTR     www.kham.site.
31      IN      PTR     www.kham.com.
EOF'

echo "Step 9: Check configuration"
sudo named-checkconf
sudo named-checkzone kham.site /etc/bind/db.kham.site
sudo named-checkzone kham.com /etc/bind/db.kham.com
sudo named-checkzone 10.168.192.in-addr.arpa /etc/bind/db.192.168.10

echo "Step 10: Restart BIND9"
sudo systemctl restart bind9
sudo systemctl enable bind9

echo "Step 11: Configure firewall"
sudo ufw allow 53/tcp
sudo ufw allow 53/udp
sudo ufw --force enable

echo "✅ BIND9 DNS Server setup is complete!"
