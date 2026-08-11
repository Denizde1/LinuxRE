#!/bin/bash

# LinuxRE kullanıcı

# Şifre
echo "linuxre:linuxre" | chpasswd

# sudo yetkisi
echo "linuxre ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/linuxre
chmod 440 /etc/sudoers.d/linuxre

# SDDM autologin
mkdir -p /etc/sddm.conf.d

cat > /etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=linuxre
Session=plasma
Relogin=true
EOF

# Servisler
systemctl enable NetworkManager
systemctl enable sddm
