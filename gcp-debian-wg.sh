#!/bin/bash
# GCP debian WireGuard服务端一键脚本

# 定义常量
port=51520
serverip=$(curl -4 ip.sb)
mtu=1460
ip_list=(100 118 128 138 148 158 168 178 188)
    

# 安装WireGuard和辅助库 resolvconf、headers
echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-unstable
apt update
apt install linux-headers-$(uname -r) -y
apt install wireguard resolvconf -y

# 安装二维码插件,方便手机扫瞄添加配置
if [ ! -f '/usr/bin/qrencode' ]; then
    apt -y install qrencode
fi

# 配置WireGuard文件目录 /etc/wireguard
mkdir -p /etc/wireguard
cd /etc/wireguard

# 生成 密匙对(公匙+私匙)
wg genkey | tee sprivatekey | wg pubkey > spublickey
wg genkey | tee cprivatekey | wg pubkey > cpublickey

# 生成服务端配置文件
cat <<EOF >wg0.conf
[Interface]
PrivateKey = $(cat sprivatekey)
Address = 10.0.0.1/24
MTU = $mtu

[Peer]
PublicKey = $(cat cpublickey)
AllowedIPs = 10.0.0.100/32

EOF

# 生成客户端配置
cat <<EOF >client.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = 10.0.0.100/24
DNS = 10.0.0.1
#  MTU = $mtu
#  PreUp =  start   .\route\routes-up.bat
#  PostDown = start  .\route\routes-down.bat

[Peer]
PublicKey = $(cat spublickey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

EOF

# 添加 1-8 号多用户配置
for i in {1..8}
do
    ip=10.0.0.${ip_list[$i]}
    wg genkey | tee cprivatekey | wg pubkey > cpublickey

    cat <<EOF >>wg0.conf
[Peer]
PublicKey = $(cat cpublickey)
AllowedIPs = $ip/32

EOF

    cat <<EOF >wg_client_$i.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = $ip/24
DNS = 10.0.0.1

[Peer]
PublicKey = $(cat spublickey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

EOF
    cat /etc/wireguard/wg_client_$i.conf | qrencode -o wg_client_$i.png
done

# 启动WireGuard
chown -v root:root /etc/wireguard/wg0.conf
chmod -v 600 /etc/wireguard/wg0.conf
wg-quick up wg0

#Enables the interface on boot
systemctl enable wg-quick@wg0 

# Enable ipv4 ip forward
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# configure firewall rules
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

iptables -A INPUT -p udp -m udp --dport 51520 -m conntrack --ctstate NEW -j ACCEPT

iptables -A INPUT -s 10.0.0.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.0.0.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT

iptables -A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT

iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

#save the iptables
apt install iptables-persistent -y
systemctl enable netfilter-persistent
netfilter-persistent save


