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

inner=$(hostname -I | awk '{print $1}')
kubeadm init --pod-network-cidr=192.168.0.0/16 --upload-certs --control-plane-endpoint=$inner --apiserver-advertise-address=$inner --service-cidr=172.36.1.0/24 --v=5 --cri-socket  unix:///var/run/cri-dockerd.sock

#k8s初始成功
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# k8s安装网络插件
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.1/manifests/custom-resources.yaml

# 安装jq
sudo apt-get install jq -y
# *****************************
# 等待pod变为running状态
# watch kubectl get pods -n calico-system
NAMESPACE="calico-system"
while true; do
    # 获取所有 Pods 的状态
    PODS_STATUS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running -o json)
    # 检查是否有不在 Running 状态的 Pod
    if [ $(echo "$PODS_STATUS" | jq '.items | length') -eq 0 ]; then
        echo "所有 Pods 都在 Running 状态！"
        break
    else
        echo "还有 Pods 不在 Running 状态，继续监控..."
        sleep 5  # 暂停 5 秒后再检查
    fi
done
# *****************************
# 去除k8s master节点污点，否则无法正常调度pod
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-

# 安装 Ingress-nginx 控制器
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.7.1/deploy/static/provider/cloud/deploy.yaml
kubectl get pod -n ingress-nginx

# 提取出ingress-nginx外部端口
# kubectl get svc -n ingress-nginx
nginx_out_port=$(kubectl get svc -n ingress-nginx -o=jsonpath='{.items[?(@.metadata.name=="ingress-nginx-controller")].spec.ports[?(@.port==80)].nodePort}')

#安装nginx
sudo apt update
sudo apt install nginx -y

read -p '输入泛域名：' domain;
# *****************************
# 将下面内容写入配置文件中 
# vim /etc/nginx/conf.d/swan.conf 
#需要修改为一件写入
# map $http_upgrade $connection_upgrade {
#     default upgrade;
#     ''      close;
# }
# server {
#         listen 80;
#         listen [::]:80;
#         server_name *.aaglobal.top;   # 此处的*.cp.testnet.cn需要修改为你的域名，*号不要删除 
#         return 301 https://$host$request_uri;
#         #client_max_body_size 1G;
# }
# server {
#         listen 443 ssl;
#         listen [::]:443 ssl;
#         ssl_certificate  fullchain.pem;     # 修改为你的ssl证书文件所在路径
#         ssl_certificate_key  privkey.key;   # 修改为你的ssl证书文件所在路径

#         server_name *.aaglobal.top;       # 此处的*.cp.testnet.cn需要修改为你的域名，*号不要删除
#         location / {
#           proxy_pass http://127.0.0.1:30440;  # 这里反向代理的 <port>需要修改为上一步 Ingress-nginx 的端口
#           proxy_set_header Host $http_host;
#           proxy_set_header Upgrade $http_upgrade;
#           proxy_set_header Connection $connection_upgrade;
#        }
# }
# *****************************
# nginx配置文件改好之后，检查配置文件是否正确，并重载nginx
nginx -t
nginx -s reload

# *****************************
# 去浏览器访问一下自己的域名，看ssl证书是否配置正确，如果不正确浏览器会提示证书不安全。
# https://xxx.cp.testnet.cn

# *****************************
# 安装resource-exporter
# 此插件的作用是向官方汇报本机硬件配置信息，如果你的机器配置太低，可能会接不到任务
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  namespace: kube-system
  name: resource-exporter-ds
  labels:
    app: resource-exporter
spec:
  selector:
    matchLabels:
      app: resource-exporter
  template:
    metadata:
      labels:
        app: resource-exporter
    spec:
      containers:
      - name: resource-exporter
        image: filswan/resource-exporter:v11.2.8
        imagePullPolicy: IfNotPresent
EOF
# *****************************
# 安装正确，执行 kubectl get po -n kube-system 可以看到resource-exporter正在Running
kubectl get po -n kube-system
# *****************************
# 安装redis
sudo apt update
sudo apt install -y redis-server
systemctl start redis-server.service
# *****************************
# 安装 computing-provider
# 官方提供了一个二进制程序，可以直接下载运行
mkdir -p /data/swan/ && cd /data/swan/
wget https://github.com/swanchain/go-computing-provider/releases/download/v0.6.2/computing-provider
chmod +x computing-provider
ln -s /data/swan/computing-provider /usr/local/bin/
computing-provider -v
# *****************************
# 配置computing-provider程序的环境变量
echo 'export CP_PATH=/data/swan' >> /etc/profile
echo 'export FIL_PROOFS_PARAMETER_CACHE=/var/tmp/filecoin-proof-parameters' >> /etc/profile
source /etc/profile  &&  echo $CP_PATH && echo $FIL_PROOFS_PARAMETER_CACHE
# *****************************
# 安装AI推理依赖
mkdir -p /data/swan/src  &&  cd /data/swan/src
wget https://github.com/swanchain/go-computing-provider/archive/refs/tags/v0.6.2.tar.gz
tar xvf v0.6.2.tar.gz
cd go-computing-provider-0.6.2/
export CP_PATH=/data/swan
./install.sh
# *****************************
# 下载UBI文件
# 总大小约160G，下载完成后才能正常接收ubi任务
# 下载文件过大，为防止远程会话中断，建议先开启一个screen再下载文件。
# 下载比较慢，这个screen会话先挂着，新开一个会话，继续执行后续步骤
screen -S  ubi   # 如果此窗口中断，可使用 screen -r  ubi 恢复
export PARENT_PATH=/var/tmp/filecoin-proof-parameters
# 512MiB parameters
curl -fsSL https://raw.githubusercontent.com/swanchain/go-computing-provider/releases/ubi/fetch-param-512.sh | bash
# 32GiB parameters
curl -fsSL https://raw.githubusercontent.com/swanchain/go-computing-provider/releases/ubi/fetch-param-32.sh | bash


# *****************************
# 指定 ubi文件的下载路径
cd /data/swan
cat > fil-c2.env << EOF
FIL_PROOFS_PARAMETER_CACHE="/var/tmp/filecoin-proof-parameters"
EOF
# *****************************
read -p '节点名称:' node_name
public_ip=$(curl ifconfig.me)
echo '初始化钱包'
echo ''
computing-provider init --multi-address=/ip4/$public_ip/tcp/8085 --node-name=$node_name
echo '导出钱包私钥'
echo ''
computing-provider wallet new
# *****************************
# eth主网跨链至swan链
# *****************************
# 查看swan余额
computing-provider wallet list
# *****************************
#需要改动
computing-provider account create --ownerAddress 上一步创建的地址 \
 --workerAddress 上一步创建的地址 \
 --beneficiaryAddress 上一步创建的地址 \
 --task-types 3
# *****************************
# 查看CP信息
 computing-provider info
