#!bin/bash
ip_list = (100 110 118 128 138 148 158 168 178 188)
for i in {2..9}
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
DNS = 8.8.8.8
[Peer]
PublicKey = $(cat spublickey)
Endpoint = 35.220.145.148:51520
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    cat /etc/wireguard/wg_client_$i.conf | qrencode -o wg_client_$i.png
done
