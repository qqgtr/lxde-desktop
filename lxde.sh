#!/bin/bash

# ==============================================================================
# 脚本名称: 多系统兼容纯净 LXDE 中文桌面 + 双远程工具智能带宽交互调优一键脚本
# 支持系统: Debian 11+ , Ubuntu 22.04+  [以 Root 权限运行]
# ==============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# GitHub 代理加速节点配置
GH_PROXY="https://gh-proxy.com"

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本！${PLAIN}"
    exit 1
fi

# 检测系统发行版与主版本号
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$ID
    # 提取主版本号数字 (例如 "22.04" -> 22, "12" -> 12)
    OS_MAJOR=$(echo "$VERSION_ID" | cut -d'.' -f1)
else
    echo -e "${RED}错误: 无法识别当前操作系统！${PLAIN}"
    exit 1
fi

# 系统兼容性阻断检查
COMPATIBLE=0
if [ "$OS_NAME" = "debian" ] && [ "$OS_MAJOR" -ge 11 ]; then
    COMPATIBLE=1
elif [ "$OS_NAME" = "ubuntu" ] && [ "$OS_MAJOR" -ge 22 ]; then
    COMPATIBLE=1
fi

if [ $COMPATIBLE -eq 0 ]; then
    echo -e "${RED}错误: 本脚本仅支持 Debian 11+ 和 Ubuntu 22.04+ 系统！${PLAIN}"
    echo -e "当前检测系统为: ${YELLOW}${OS_NAME} ${VERSION_ID}${PLAIN}"
    exit 1
fi

echo -e "${BLUE}====================================================${PLAIN}"
echo -e "${GREEN}    欢迎使用 LXDE 中文桌面智能交互安装脚本${PLAIN}"
echo -e "${BLUE}====================================================${PLAIN}"
echo -e "当前系统检测结果: ${YELLOW}${OS_NAME} ${VERSION_ID} (主版本: ${OS_MAJOR})${PLAIN}\n"

# 交互获取用户网络带宽
echo -e "${BLUE}[网络参数交互采集]${PLAIN}"
read -p "1. 请输入当前机器的 [外网上传带宽] (单位 Mbps, 纯数字, 默认 5): " NET_UP
NET_UP=${NET_UP:-5}

# 验证上传带宽是否为数字
if ! [[ "$NET_UP" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误: 上传带宽必须是纯数字，已使用默认值 5 Mbps${PLAIN}"
    NET_UP=5
fi

read -p "2. 请输入当前机器的 [外网下载带宽] (单位 Mbps, 纯数字, 默认 200): " NET_DOWN
NET_DOWN=${NET_DOWN:-200}

# 验证下载带宽是否为数字
if ! [[ "$NET_DOWN" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误: 下载带宽必须是纯数字，已使用默认值 200 Mbps${PLAIN}"
    NET_DOWN=200
fi

echo -e "\n${GREEN}网络配置已锁定 -> 上传: ${NET_UP}Mbps / 下载: ${NET_DOWN}Mbps。开始执行部署...${PLAIN}\n"

# 1. 更新系统源并安装基础及多系统兼容依赖包
echo -e "${BLUE}[1/11] 更新系统并安装环境所需的底座依赖...${PLAIN}"
apt update && apt upgrade -y

# 核心通用依赖池
BASE_PKGS="sudo curl wget vim locales ttf-wqy-zenhei xfonts-intl-chinese \
libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libgtk-3-0 libgbm1 libasound2 \
libsecret-1-0 leafpad xarchiver zip unzip p7zip-full tar gzip bzip2"

# 根据系统大版本，精确处理依赖和组件包名差异
if [ "$OS_NAME" = "debian" ]; then
    BASE_PKGS="${BASE_PKGS} task-lists"
    if [ "$OS_MAJOR" -eq 11 ]; then
        BASE_PKGS="${BASE_PKGS} libwebkit2gtk-4.0-3"
    else
        BASE_PKGS="${BASE_PKGS} libwebkit2gtk-4.1-0"
    fi
elif [ "$OS_NAME" = "ubuntu" ]; then
    BASE_PKGS="${BASE_PKGS} software-properties-common"
    if [ "$OS_MAJOR" -eq 22 ]; then
        BASE_PKGS="${BASE_PKGS} libwebkit2gtk-4.0-3"
    else
        BASE_PKGS="${BASE_PKGS} libwebkit2gtk-4.1-0"
    fi
fi

apt install -y $BASE_PKGS

# 2. 安装极简纯净 LXDE 桌面与 XRDP (无 LightDM)
echo -e "${BLUE}[2/11] 安装轻量纯净 LXDE 桌面核心与远程桌面服务...${PLAIN}"
apt install -y xorg lxde-core xrdp fcitx5 fcitx5-pinyin lxterminal

# 注入全局和 root 用户环境会话变量
mkdir -p /etc/skel /root
ENV_SESSIONS="export LANG=zh_CN.UTF-8\nexport XDG_DATA_DIRS=/usr/share/lxde:/usr/local/share:/usr/share\nlxsession -s LXDE -e LXDE"
echo -e "$ENV_SESSIONS" > /etc/skel/.xsession
echo -e "$ENV_SESSIONS" > /root/.xsession
# 必须给 .xsession 添加可执行权限，否则 XRDP 无法启动桌面会话
chmod +x /etc/skel/.xsession /root/.xsession

# 3. 优化 XRDP 会话管理与智能图像压缩调优
echo -e "${BLUE}[3/11] 正在根据用户输入的上传带宽 (${NET_UP}Mbps) 调优图像压缩算法...${PLAIN}"
if [ -f /etc/xrdp/xrdp.ini ]; then
    sed -i 's/MaxSessions=.*/MaxSessions=10/g' /etc/xrdp/xrdp.ini
    if ! grep -q "MaxSessions" /etc/xrdp/xrdp.ini; then
        sed -i '/\[globals\]/a MaxSessions=10' /etc/xrdp/xrdp.ini
    fi
    
    # 智能干预图像色深（10M为低带宽分水岭）
    if [ "$NET_UP" -le 10 ]; then
        echo -e "${YELLOW}检测为低上传带宽限制，强制启用 16-bit 深度画面压缩流...${PLAIN}"
        sed -i 's/max_bpp=.*/max_bpp=16/g' /etc/xrdp/xrdp.ini
        sed -i 's/xrdp.bpp=.*/xrdp.bpp=16/g' /etc/xrdp/xrdp.ini
    else
        echo -e "${GREEN}上传带宽充裕，采用 32-bit 高清图形流渲染...${PLAIN}"
        sed -i 's/max_bpp=.*/max_bpp=32/g' /etc/xrdp/xrdp.ini
        sed -i 's/xrdp.bpp=.*/xrdp.bpp=32/g' /etc/xrdp/xrdp.ini
    fi
    
    sed -i 's/use_compression=.*/use_compression=yes/g' /etc/xrdp/xrdp.ini
    sed -i 's/crypt_level=.*/crypt_level=low/g' /etc/xrdp/xrdp.ini
fi

if [ -f /etc/xrdp/sesman.ini ]; then
    # 调大会话超时时间，避免刚连接就断开会话
    sed -i 's/DisconnectedSessionExpiryTime=.*/DisconnectedSessionExpiryTime=300/g' /etc/xrdp/sesman.ini
    sed -i 's/IdleSessionExpiryTime=.*/IdleSessionExpiryTime=600/g' /etc/xrdp/sesman.ini
fi

# 修改 startwm.sh 确保正确启动 LXDE 桌面
if [ -f /etc/xrdp/startwm.sh ]; then
    # 备份原始文件
    cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak 2>/dev/null
    
    # 写入新的启动脚本，确保启动 LXDE
    cat > /etc/xrdp/startwm.sh << 'STARTWM'
#!/bin/sh
# xrdp session startup script

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# 优先使用用户的 .xsession
if [ -x "$HOME/.xsession" ]; then
  exec "$HOME/.xsession"
fi

# 回退到系统默认 LXDE 会话
exec startlxde
STARTWM
    chmod +x /etc/xrdp/startwm.sh
fi

# 配置 polkit 规则放行 XRDP 会话，避免认证弹窗阻塞桌面启动
mkdir -p /etc/polkit-1/localauthority/50-local.d
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla << 'POLKIT'
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
POLKIT

systemctl enable xrdp
systemctl restart xrdp

# 4. 跨系统兼容安装超轻量现代浏览器
echo -e "${BLUE}[4/11] 正在安装极简浏览器...${PLAIN}"
apt install -y midori 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}当前发行版仓库未提供 midori，正在自动切换备用极简浏览器 epiphany-browser...${PLAIN}"
    apt install -y epiphany-browser
fi

# 5. 【项目一】下载并安装 Netcatty SSH 客户端
echo -e "${BLUE}[5/11] 正在通过代理加速节点获取并安装 Netcatty (binaricat/Netcatty)...${PLAIN}"
# API 请求不使用代理（gh-proxy 不支持 api.github.com）
NC_API_URL="https://api.github.com/repos/binaricat/Netcatty/releases/latest"
# 匹配 linux-amd64.deb 或 amd64.deb
NC_RAW_URL=$(curl -s "$NC_API_URL" | grep -E "browser_download_url.*linux-amd64\.deb|browser_download_url.*amd64\.deb" | head -n 1 | cut -d '"' -f 4)

if [ -z "$NC_RAW_URL" ]; then
    echo -e "${YELLOW}API 解析失败，无法获取 Netcatty 下载链接...${PLAIN}"
    echo -e "${RED}错误: Netcatty 下载失败！${PLAIN}"
else
    NC_URL="${GH_PROXY}/${NC_RAW_URL}"
    wget -O /tmp/netcatty.deb "$NC_URL"
    if [ -f /tmp/netcatty.deb ] && [ -s /tmp/netcatty.deb ]; then
        dpkg -i /tmp/netcatty.deb || apt-get install -f -y
        rm -f /tmp/netcatty.deb
    else
        echo -e "${RED}错误: Netcatty 下载失败！${PLAIN}"
    fi
fi

# 6. 【项目二】下载并安装 OxideTerm SSH 客户端
echo -e "${BLUE}[6/11] 正在通过代理加速节点获取并安装 OxideTerm (AnalyseDeCircuit/oxideterm)...${PLAIN}"
# API 请求不使用代理（gh-proxy 不支持 api.github.com）
OX_API_URL="https://api.github.com/repos/AnalyseDeCircuit/oxideterm/releases/latest"
# 匹配 x64.deb 或 amd64.deb
OX_RAW_URL=$(curl -s "$OX_API_URL" | grep -E "browser_download_url.*linux_x64\.deb|browser_download_url.*amd64\.deb" | head -n 1 | cut -d '"' -f 4)

if [ -z "$OX_RAW_URL" ]; then
    echo -e "${YELLOW}API 解析失败，无法获取 OxideTerm 下载链接...${PLAIN}"
    echo -e "${RED}错误: OxideTerm 下载失败！${PLAIN}"
else
    OX_URL="${GH_PROXY}/${OX_RAW_URL}"
    wget -O /tmp/oxideterm.deb "$OX_URL"
    if [ -f /tmp/oxideterm.deb ] && [ -s /tmp/oxideterm.deb ]; then
        dpkg -i /tmp/oxideterm.deb || apt-get install -f -y
        rm -f /tmp/oxideterm.deb
    else
        echo -e "${RED}错误: OxideTerm 下载失败！${PLAIN}"
    fi
fi

# 7. 全自动安全部署快捷方式 (仅快捷方式，无任何自启动)
echo -e "${BLUE}[7/11] 正在跨系统动态生成桌面快捷方式结构...${PLAIN}"
mkdir -p /root/桌面 /root/Desktop /etc/skel/桌面 /etc/skel/Desktop

copy_desktop_icon() {
    local pattern=$1
    local found_file=$(find /usr/share/applications/ -maxdepth 1 -iname "*${pattern}*.desktop" | head -n 1)
    if [ ! -z "$found_file" ] && [ -f "$found_file" ]; then
        cp "$found_file" /root/桌面/ && cp "$found_file" /etc/skel/桌面/
    fi
}

copy_desktop_icon "midori"
copy_desktop_icon "epiphany"
copy_desktop_icon "leafpad"
copy_desktop_icon "xarchiver"
copy_desktop_icon "netcatty"
copy_desktop_icon "oxideterm"

# 针对 Electron 核心的 Netcatty 在 Root 下的沙盒闪退 Bug 进行补修
# 动态检测 Netcatty 实际安装路径
NC_EXEC_PATH=""
for nc_path in /usr/bin/netcatty /opt/Netcatty/netcatty /usr/local/bin/netcatty; do
    if [ -f "$nc_path" ]; then
        NC_EXEC_PATH="$nc_path"
        break
    fi
done

# 如果找到可执行文件，则修复桌面文件
if [ -n "$NC_EXEC_PATH" ]; then
    # 使用 -iname 大小写不敏感匹配，覆盖所有可能的桌面文件位置
    for DESKTOP_FILE in $(find /usr/share/applications/ /root/桌面/ /etc/skel/桌面/ -maxdepth 1 -iname "*netcatty*.desktop" 2>/dev/null); do
        if [ -f "$DESKTOP_FILE" ]; then
            # 备份原文件
            cp "$DESKTOP_FILE" "$DESKTOP_FILE.bak" 2>/dev/null
            
            # 只修改包含 netcatty 的 Exec 行（不区分大小写），保留原始大小写
            # 使用更精确的正则：匹配 Exec= 开头，且行中包含 netcatty（忽略大小写）
            if grep -qi "^Exec=.*netcatty" "$DESKTOP_FILE"; then
                # 如果还没有 --no-sandbox，则添加
                if ! grep -q "\-\-no-sandbox" "$DESKTOP_FILE"; then
                    # 使用 perl 进行更精确的替换，保留原始大小写
                    perl -i -pe 's/^(Exec=.*)$/$1 --no-sandbox/i if /netcatty/i' "$DESKTOP_FILE"
                    echo "已为 $DESKTOP_FILE 添加 --no-sandbox 参数"
                fi
            fi
        fi
    done
    
    # 同时创建命令行启动脚本，方便直接运行
    cat > /usr/local/bin/netcatty-root << EOF
#!/bin/bash
# Netcatty root 用户启动包装器
exec $NC_EXEC_PATH --no-sandbox "\$@"
EOF
    chmod +x /usr/local/bin/netcatty-root 2>/dev/null
fi

cp -r /root/桌面/* /root/Desktop/ 2>/dev/null
cp -r /etc/skel/桌面/* /etc/skel/Desktop/ 2>/dev/null
chmod +x /root/桌面/*.desktop /root/Desktop/*.desktop /etc/skel/桌面/*.desktop /etc/skel/Desktop/*.desktop 2>/dev/null

# 8. 配置 PCManFM 文件管理器右键一键解压菜单
echo -e "${BLUE}[8/11] 配置 PCManFM 文件管理器右键菜单增强...${PLAIN}"
mkdir -p /root/.local/share/file-manager/actions
mkdir -p /etc/skel/.local/share/file-manager/actions

cat <<EOF > /root/.local/share/file-manager/actions/xarchiver-extract.desktop
[Desktop Action xarchiver-extract]
Name=使用 Xarchiver 提取到当前文件夹
Name[zh_CN]=使用 Xarchiver 提取到当前文件夹
Icon=xarchiver
Exec=xarchiver -e %f

[Desktop Entry]
Type=Action
Profiles=profile-zero;
Name=使用 Xarchiver 提取
Name[zh_CN]=使用 Xarchiver 提取

[X-Action-Profile profile-zero]
MimeTypes=application/x-7z-compressed;application/zip;application/x-tar;application/x-gzip;application/x-bzip2;
Exec=xarchiver -e %f
EOF
cp /root/.local/share/file-manager/actions/xarchiver-extract.desktop /etc/skel/.local/share/file-manager/actions/

# 9. 深度性能调优：高并发内核网卡与智能网络接收窗口计算
echo -e "${BLUE}[9/11] 正在基于下载带宽 (${NET_DOWN}Mbps) 注入动态内核 TCP 调优限制...${PLAIN}"

# 检查是否已存在配置标记，避免重复追加
if ! grep -q "# LXDE-DESKTOP-TUNING" /etc/security/limits.conf 2>/dev/null; then
    cat <<EOF >> /etc/security/limits.conf
# LXDE-DESKTOP-TUNING
*               soft    nofile          65535
*               hard    nofile          65535
*               soft    nproc           4096
*               hard    nproc           4096
*               soft    memlock         unlimited
*               hard    memlock         unlimited
EOF
fi

if ! grep -q "# LXDE-DESKTOP-TUNING" /etc/sysctl.conf 2>/dev/null; then
    cat <<EOF >> /etc/sysctl.conf
# LXDE-DESKTOP-TUNING
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
fs.file-max = 65535
EOF
fi

# 动态扩展高带宽接收窗口（如果下载带宽大于 100Mbps 触发）
if [ "$NET_DOWN" -gt 100 ]; then
    if ! grep -q "# LXDE-DESKTOP-HIGH-BW" /etc/sysctl.conf 2>/dev/null; then
        cat <<EOF >> /etc/sysctl.conf
# LXDE-DESKTOP-HIGH-BW
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
    fi
fi
sysctl -p 2>/dev/null

# 10. 系统瘦身与垃圾清理
echo -e "${BLUE}[10/11] 清理缓存文件释放系统体积...${PLAIN}"
apt autoremove -y && apt clean

# 11. 配置全中文环境（放在最后执行，确保所有组件安装完成后再设置中文）
echo -e "${BLUE}[11/11] 配置系统中文本地化 (UTF-8)...${PLAIN}"
sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen
locale-gen
update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh
export LANG=zh_CN.UTF-8

# 部署完成提示
echo -e "\n${GREEN}====================================================${PLAIN}"
echo -e "${GREEN} 恭喜！多系统兼容（Debian 11+ / Ubuntu 22.04+）部署成功！${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
echo -e "${YELLOW}当前环境版本及网络调优状态：${PLAIN}"
echo -e "▶ 宿主系统版本: ${GREEN}${OS_NAME} ${VERSION_ID}${PLAIN}"
echo -e "▶ 目标用户网络: [上传: ${NET_UP} Mbps] / [下载: ${NET_DOWN} Mbps]"
if [ "$NET_UP" -le 10 ]; then
    echo -e "▶ RDP 调优反馈: ${RED}低带宽防卡顿模式已激活（16位色高压缩传输）${PLAIN}"
else
    echo -e "▶ RDP 调优反馈: ${GREEN}宽带充足模式已激活（32位高清色渲染输出）${PLAIN}"
fi

echo -e "▶ 远程连接通道: Windows 远程桌面 (RDP) 连接服务器 3389 端口"
echo -e "▶ 桌面运维客户端: 桌面上已生成 Netcatty 和 OxideTerm 两个现代 SSH 工具"
echo -e "▶ 注意事项:     请确保您的云服务器控制台（安全组）已开放 3389 端口！"
echo -e "${GREEN}====================================================${PLAIN}"

# 提示是否重启
read -p "是否现在重启系统以使所有优化生效？(y/n): " REBOOT_CHOICE
if [ "$REBOOT_CHOICE" = "y" ] || [ "$REBOOT_CHOICE" = "Y" ]; then
    reboot
fi
