wget -c https://golang.org/dl/go1.21.7.linux-amd64.tar.gz -O - | sudo tar -xz -C /usr/local

echo "export PATH=$PATH:/usr/local/go/bin" >> ~/.bashrc && source ~/.bashrc

go version

# 安装docker
apt update && apt install docker.io -y

# 设置docker的cgroupdriver为systemd
cat > /etc/docker/daemon.json << EOF
{
    "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

# 重启docker
systemctl restart docker

# 安装cri-dockerd
wget https://testnetcn.oss-cn-hangzhou.aliyuncs.com/src/cri-dockerd_0.3.3.3-0.ubuntu-jammy_amd64.deb
dpkg -i cri-dockerd_0.3.3.3-0.ubuntu-jammy_amd64.deb
systemctl status cri-docker.service

# 安装kubeadm
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

apt-get update && apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# 初始化k8s
swapoff -a
# 可以注释掉 /etc/fstab 文件里swap那一行，防止服务器重启后swap又起来。

inner=hostname -I | awk '{print $1}'
kubeadm init --pod-network-cidr=192.168.0.0/16 --upload-certs --control-plane-endpoint=服务器内网IP --apiserver-advertise-address=服务器内网IP --service-cidr=172.36.1.0/24 --v=5 --cri-socket  unix:///var/run/cri-dockerd.sock
