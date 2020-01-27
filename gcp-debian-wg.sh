#!/bin/bash
# GCP debian WireGuard服务端一键脚本

# 定义常量
port=51520
serverip=$(curl -4 ip.sb)
mtu=1360
ip_list=(100 118 128 138 148 158 168 178 188)
ipv6_range="fd08:620c:4df0:65eb::"
    

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
chmod 755 /etc/wireguard
cd /etc/wireguard

# 生成 密匙对(公匙+私匙),add Presharedkey
wg genkey | tee sprivatekey | wg pubkey > spublickey
wg genkey | tee cprivatekey | wg pubkey > cpublickey | wg genpsk > presharedkey

# 生成服务端配置文件
cat <<EOF >wg0.conf
[Interface]
PrivateKey = $(cat sprivatekey)
Address = 10.18.0.1/24, ${ipv6_range}1/64
ListenPort = 51520
MTU = $mtu
# DNS = 8.8.8.8, 2001:4860:4860::8888

[Peer]
PublicKey = $(cat cpublickey)
PresharedKey = $(cat presharedkey)
AllowedIPs = 10.18.0.100/32, ${ipv6_range}100
EOF

# 生成客户端配置
cat <<EOF >client.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = 10.18.0.100/24, ${ipv6_range}100/64
MTU = $mtu
# DNS = 8.8.8.8, 2001:4860:4860::8888
#  PreUp =  start   .\route\routes-up.bat
#  PostDown = start  .\route\routes-down.bat

[Peer]
PublicKey = $(cat spublickey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

# 添加 1-8 号多用户配置
for i in {1..8}
do
    ip=10.18.0.${ip_list[$i]}
    ip6=${ipv6_range}${ip_list[$i]}
   
    wg genkey | tee cprivatekey | wg pubkey > cpublickey | wg genpsk > presharedkey

    cat <<EOF >>wg0.conf
[Peer]
PublicKey = $(cat cpublickey)
PresharedKey = $(cat presharedkey)
AllowedIPs = $ip/32, $ip6
EOF

    cat <<EOF >client_$i.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = $ip/24, $ip6/64
MTU = $mtu
# DNS = 8.8.8.8, 2001:4860:4860::8888

[Peer]
PublicKey = $(cat spublickey)
PresharedKey = $(cat presharedkey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF
done

# 启动WireGuard
chown -v root:root /etc/wireguard/wg0.conf
chmod -v 600 /etc/wireguard/wg0.conf
wg-quick up wg0

#Enables the interface on boot
systemctl enable wg-quick@wg0 

# Enable ip forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# configure firewall rule. 
# Attenation: check below port and ip address and NIC before change iptables.
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p udp -m udp --dport 51520 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.18.0.0/24 -p tcp -m tcp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -s 10.18.0.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
iptables -A FORWARD -i wg0 -o wg0 -m conntrack --ctstate NEW -j ACCEPT
iptables -t nat -A POSTROUTING -s 10.18.0.0/24 -o eth0 -j MASQUERADE
