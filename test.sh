#!/bin/bash

# ========== 参数 ==========
API_URL="http://10.31.14.57:8000/v1/chat/completions"
MODEL="DeepSeek-Llama-70B"
# API_URL="192.168.1.89:1040/v1/chat/completions"
# MODEL="DeepSeek-R1-Distill-Qwen-32B"
CONCURRENCY=5  # 并发数
MAX_TOKENS=512

# curl http://10.31.14.57:8000/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{
#     "model": "DeepSeek-Llama-70B",
#     "messages": [
#       {"role": "system", "content": "你是一个有帮助的助手。"},
#       {"role": "user", "content": "你好，帮我写一个排序算法。"}
#     ],
#     "temperature": 0.7,
#     "max_tokens": 256
#   }'
qwasdasdDASD


# ========== 颜色 ==========
GREEN="\033[1;32m"
BLUE="\033[1;34m"
RED="\033[1;31m"
RESET="\033[0m"

# ========== 检查依赖 ==========
for cmd in jq bc; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}缺少依赖：$cmd，请先安装！${RESET}"
    exit 1
  fi
done

# ========== 工具函数 ==========
calc_speed() {
  local tokens=$1
  local time_ms=$2
  echo "scale=2; $tokens * 1000 / $time_ms" | bc
}

print_section() {
  echo -e "\n${BLUE}>>> [$1] ${2}${RESET}"
}

# ========== 1. 单轮对话 ==========
print_section "1" "单轮对话耗时 & 速度"
START=$(date +%s%3N)
RESPONSE=$(curl -s -X POST $API_URL \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'$MODEL'",
    "messages": [{"role": "user", "content": "介绍一下人工智能"}],
    "temperature": 0.7,
    "max_tokens": '$MAX_TOKENS'
  }')
END=$(date +%s%3N)
ELAPSED=$((END - START))
TOKENS=$(echo "$RESPONSE" | jq '.usage.total_tokens')
SPEED=$(calc_speed "$TOKENS" "$ELAPSED")
echo -e "${GREEN}耗时：${ELAPSED} ms，生成 token 数：${TOKENS}，平均速度：${SPEED} tok/s${RESET}"

# ========== 2. 多轮流式对话 ==========
print_section "2" "多轮对话（stream）首 token 时间 & 平均速度"
STREAM_FILE="/tmp/vllm_stream.txt"
START=$(date +%s%3N)
curl -s -N -X POST $API_URL \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'$MODEL'",
    "messages": [
      {"role": "system", "content": "你是一个有帮助的AI助手"},
      {"role": "user", "content": "帮我写一个快速排序"}
    ],
    "stream": true,
    "max_tokens": '$MAX_TOKENS'
  }' > $STREAM_FILE &
PID=$!

# 等待首 token 出现
while true; do
  if grep -q "data: " "$STREAM_FILE"; then
    FIRST_TOKEN_TIME=$(($(date +%s%3N) - START))
    echo -e "${GREEN}首 token 时间：${FIRST_TOKEN_TIME} ms${RESET}"
    break
  fi
  sleep 0.01
done

wait $PID
TOTAL_TOKENS=$(grep -o '"content":' "$STREAM_FILE" | wc -l)
TOTAL_TIME=$(($(date +%s%3N) - START))
STREAM_SPEED=$(calc_speed "$TOTAL_TOKENS" "$TOTAL_TIME")
echo -e "${GREEN}总生成 token 数：${TOTAL_TOKENS}，耗时：${TOTAL_TIME} ms，平均速度：${STREAM_SPEED} tok/s${RESET}"

# ========== 3. 并发测试 ==========
print_section "3" "并发请求测试（$CONCURRENCY 并发）"
parallel_test() {
  curl -s -X POST $API_URL \
    -H "Content-Type: application/json" \
    -d '{
      "model": "'$MODEL'",
      "messages": [{"role": "user", "content": "介绍一下人工智能"}],
      "max_tokens": 100
    }' > /dev/null
}

START=$(date +%s%3N)
for ((i = 0; i < CONCURRENCY; i++)); do
  parallel_test &
done
wait
END=$(date +%s%3N)
TOTAL=$((END - START))
echo -e "${GREEN}并发 $CONCURRENCY 请求总耗时：${TOTAL} ms${RESET}"
