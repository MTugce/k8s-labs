#!/usr/bin/env bash
set -e

# Renk tanımlamaları
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   Kubernetes Labs Altyapı Kurulum Betiği (Ubuntu)  ${NC}"
echo -e "${BLUE}====================================================${NC}"

# 1. Temel Sistem Paketleri
echo -e "\n${YELLOW}>>> [1/6] Temel paketler kontrol ediliyor...${NC}"
sudo apt-get update -y -q
sudo apt-get install -y -q apt-transport-https ca-certificates curl gnupg lsb-release git conntrack jq

# 2. Docker Kurulumu
echo -e "\n${YELLOW}>>> [2/6] Docker kontrol ediliyor...${NC}"
if command -v docker &>/dev/null; then
    echo -e "${GREEN}✓ Docker zaten kurulu: $(docker --version)${NC}"
else
    echo "Docker bulunamadı, resmi Docker deposundan kuruluyor..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y -q
    sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    echo -e "${GREEN}✓ Docker başarıyla kuruldu.${NC}"
fi

# Mevcut kullanıcıyı docker grubuna ekle
sudo usermod -aG docker "$USER" 2>/dev/null || true

# 3. Kubectl Kurulumu
echo -e "\n${YELLOW}>>> [3/6] kubectl kontrol ediliyor...${NC}"
if command -v kubectl &>/dev/null; then
    echo -e "${GREEN}✓ kubectl zaten kurulu: $(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion || kubectl version --client)${NC}"
else
    echo "kubectl bulunamadı, resmi kaynaktan kuruluyor..."
    K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    ARCH=$(dpkg --print-architecture)
    curl -sLO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
    echo -e "${GREEN}✓ kubectl ($K8S_VERSION) kuruldu.${NC}"
fi

# 4. Kind Kurulumu
echo -e "\n${YELLOW}>>> [4/6] kind kontrol ediliyor...${NC}"
if command -v kind &>/dev/null; then
    echo -e "${GREEN}✓ kind zaten kurulu: $(kind version)${NC}"
else
    echo "kind bulunamadı, kuruluyor..."
    KIND_VERSION="v0.33.0"
    ARCH=$(dpkg --print-architecture)
    curl -sLo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo -e "${GREEN}✓ kind ($KIND_VERSION) kuruldu.${NC}"
fi

# 5. Helm Kurulumu
echo -e "\n${YELLOW}>>> [5/6] helm kontrol ediliyor...${NC}"
if command -v helm &>/dev/null; then
    echo -e "${GREEN}✓ helm zaten kurulu: $(helm version --short)${NC}"
else
    echo "helm bulunamadı, kuruluyor..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo -e "${GREEN}✓ helm kuruldu.${NC}"
fi

# 6. Static PV Dizin Hazırlığı (Lab 05 ve Kind için zorunlu)
echo -e "\n${YELLOW}>>> [6/6] Static PV host dizini hazırlanıyor...${NC}"
sudo mkdir -p /opt/k8s-labs/static-pv
sudo chmod 0777 /opt/k8s-labs/static-pv
echo -e "${GREEN}✓ /opt/k8s-labs/static-pv hazır.${NC}"

echo -e "\n${GREEN}====================================================${NC}"
echo -e "${GREEN}✓ Tüm altyapı araçları hazır!                       ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Şimdi Kind cluster'ı oluşturabilirsiniz:"
echo -e "  cd ~/k8s-labs"
echo -e "  kind create cluster --name k8s-labs --config kind-cluster.yaml"
