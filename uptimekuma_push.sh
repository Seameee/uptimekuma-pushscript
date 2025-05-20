#!/bin/bash

# 加载同目录下的 .env 文件
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
else
    echo "错误：找不到 .env 文件！"
    exit 1
fi

# 检查必要的变量是否已设置
if [ -z "$FULL_PUSH_URL_TEMPLATE" ] || [ -z "$PING_SERVER_IP" ]; then
    echo "错误：.env 文件中缺少 FULL_PUSH_URL_TEMPLATE 或 PING_SERVER_IP 变量！"
    exit 1
fi

# 简单的 URL 编码函数
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local char
    for (( i=0; i<strlen; i++ )); do
        char=${string:$i:1}
        case "$char" in
            [a-zA-Z0-9.~_-]) encoded+="$char" ;;
            ' ') encoded+="%20" ;; # 将空格编码为 %20
            *) printf '%%%02X' "'$char" ;;
        esac
    done
    echo "$encoded"
}

# 截取基础推送 URL
BASE_PUSH_URL=${FULL_PUSH_URL_TEMPLATE%%&msg=*}

# 获取默认网络接口名称
DEFAULT_INTERFACE=$(ip route show | grep default | awk '{print $5}')

if [ -z "$DEFAULT_INTERFACE" ]; then
    echo "错误：无法获取默认网络接口名称！"
    # 尝试查找一个常见的接口作为备用
    if ip addr show eth0 &>/dev/null; then
        DEFAULT_INTERFACE="eth0"
        echo "警告：使用备用接口 eth0"
    elif ip addr show ens33 &>/dev/null; then
        DEFAULT_INTERFACE="ens33"
        echo "警告：使用备用接口 ens33"
    else
        echo "错误：找不到常见的网络接口！"
        exit 1
    fi
fi


# 获取系统信息

# 系统型号
SYSTEM_MODEL=$(hostnamectl | grep "Static hostname" | awk '{print $3}')
if [ -z "$SYSTEM_MODEL" ]; then
    SYSTEM_MODEL=$(uname -a) # 备用方法
fi
SYSTEM_MODEL=$(echo "$SYSTEM_MODEL" | tr -d '\n') # 移除换行符

# CPU 占用率 (获取最近1秒的idle，然后计算使用率)
CPU_USAGE=$(vmstat 1 2 | tail -n 1 | awk '{print 100 - $15}')
CPU_USAGE=$(echo "$CPU_USAGE" | tr -d '\n') # 移除换行符

# 内存占用率 (%)
MEM_USAGE=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}')
MEM_USAGE=$(echo "$MEM_USAGE" | tr -d '\n') # 移除换行符

# 硬盘占用率 (根分区)
DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')
DISK_USAGE=$(echo "$DISK_USAGE" | tr -d '\n') # 移除换行符

# 上下行已用流量 (累计值)
TRAFFIC_DATA=$(cat /proc/net/dev | grep "$DEFAULT_INTERFACE" | awk '{print $2, $10}')
RX_BYTES=$(echo "$TRAFFIC_DATA" | awk '{print $1}')
TX_BYTES=$(echo "$TRAFFIC_DATA" | awk '{print $2}')

# 将字节转换为更易读的单位 (KB, MB, GB)
format_bytes() {
    local bytes=$1
    local unit=""
    if (( bytes >= 1024*1024*1024 )); then
        printf "%.2fGB" $(echo "scale=2; $bytes / (1024*1024*1024)" | bc)
    elif (( bytes >= 1024*1024 )); then
        printf "%.2fMB" $(echo "scale=2; $bytes / (1024*1024)" | bc)
    elif (( bytes >= 1024 )); then
        printf "%.2fKB" $(echo "scale=2; $bytes / 1024" | bc)
    else
        echo "${bytes}B"
    fi
}

RX_TRAFFIC=$(format_bytes "$RX_BYTES")
TX_TRAFFIC=$(format_bytes "$TX_BYTES")


# 系统在线时长
UPTIME_STR=$(uptime -p)
UPTIME_STR=$(echo "$UPTIME_STR" | sed 's/up //') # 移除 "up " 前缀
UPTIME_STR=$(echo "$UPTIME_STR" | tr -d '\n') # 移除换行符


# 获取平均 Ping 值
AVG_PING=$(ping -c 5 "$PING_SERVER_IP" | tail -n 1 | awk '{print $4}' | cut -d '/' -f 2)
AVG_PING=$(echo "$AVG_PING" | tr -d '\n') # 移除换行符

# 构建 msg 参数字符串
MSG_CONTENT="型号: ${SYSTEM_MODEL}, CPU: ${CPU_USAGE}%, Mem: ${MEM_USAGE}%, Disk: ${DISK_USAGE}, Traffic: RX ${RX_TRAFFIC} TX ${TX_TRAFFIC}, Uptime: ${UPTIME_STR}"

# 对 msg 内容进行 URL 编码
ENCODED_MSG=$(urlencode "$MSG_CONTENT")

# 构建最终的 curl URL
FULL_PUSH_URL="${BASE_PUSH_URL}&msg=${ENCODED_MSG}&ping=${AVG_PING}"

# 执行 curl 命令并记录日志
curl "${FULL_PUSH_URL}" >> /var/log/uptime_push.log 2>&1

# 脚本执行完成
echo "$(date '+%Y-%m-%d %H:%M:%S') - Uptime Kuma push executed." >> /var/log/uptime_push.log
