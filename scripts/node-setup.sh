#!/usr/bin/env bash
# From a bare Vast GPU instance (Ubuntu + CUDA) to a running llama-server: prebuilt llama.cpp, models over 16
# connections, sha256 check. About 5-10 minutes on a 1 Gbit/s host. Then: node-serve.sh flashnext-par 6
set -eu
W=/root/ws; mkdir -p $W/bin $W/models $W/slots $W/logs; cd $W
command -v aria2c >/dev/null || { apt-get update -qq && apt-get install -y -qq aria2; }
B=b12317; R=https://github.com/ggml-org/llama.cpp/releases/download/$B
QW=https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF/resolve/0669b98607d47046c7c2b3f801011d54a08cfccf
FN=https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/084c631ac221016019d6e0a863afe92d90edd3b0/UD-IQ4_XS
{
  echo $R/llama-$B-bin-ubuntu-cuda-12.8-x64.tar.gz; echo "  out=llama.tgz"
  echo $R/cudart-llama-$B-bin-ubuntu-cuda-12.8-x64.tar.gz; echo "  out=cudart.tgz"
  echo $QW/Qwen3.8-27B-Q4_K_M.gguf; echo "  out=models/Qwen3.8-27B-Q4_K_M.gguf"
  for i in 1 2 3 4; do f=Qwen3.8-Flash-Next-UD-IQ4_XS-0000$i-of-00004.gguf; echo $FN/$f; echo "  out=models/$f"; done
} > aria.list
aria2c -c -x 16 -s 16 -k 64M -j 4 --file-allocation=none --console-log-level=warn --summary-interval=60 -i aria.list
cat > sums.txt <<'S'
c872818ef519140e2dd003765668fbd852446c224a29e95d086847d9733fe2c9  llama.tgz
fc9aeae93fea730e4c3fb9c813b9dbaf50acbadd6d9177a94cc7f4460e53a074  cudart.tgz
31629f53165ab6a7dad8c9847dcfd1fdf55829dac1e6e748f4a68581b0033d34  models/Qwen3.8-27B-Q4_K_M.gguf
93ff23a08e5cd7501f24fa16f5b415d5807d0175e04edd3ed6a7a41b601a4eef  models/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf
13d5dc8b93d039e4cfade5a9af7037f10c97f7ec4e53f75bd2e9ae34aae54aeb  models/Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00004.gguf
f6b9b5934908a2043732269dd740155d0f921d0763a1dcdd3452246311651f87  models/Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00004.gguf
5de8b5dbf89409acc39468decafd4a4a95b13c29d88a14b0356107897829ec36  models/Qwen3.8-Flash-Next-UD-IQ4_XS-00004-of-00004.gguf
S
sha256sum -c sums.txt
tar xzf llama.tgz -C bin && tar xzf cudart.tgz -C bin
"$(find bin -name llama-server | head -1)" --version
