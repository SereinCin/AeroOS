#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
set -e

echo "==> update"
apt-get update -qq

echo "==> llvm 22"
wget -qO- https://apt.llvm.org/llvm.sh | bash -s 22
apt-get install -y -qq libpolly-22-dev

echo "==> qemu"
apt-get install -y -qq qemu-system-riscv64 make

echo "==> tools check"
clang --version | head -1
ld.lld --version | head -1
qemu-system-riscv64 --version | head -1

echo "==> download aero 1.2.4"
curl -fsSL https://github.com/SereinCin/aero-lang/releases/download/v1.2.4/aero-v1.2.4-linux-x86_64.tar.gz -o /tmp/aero.tar.gz
mkdir -p /tmp/ae
tar -xzf /tmp/aero.tar.gz -C /tmp/ae --no-same-permissions --no-same-owner
chmod +x /tmp/ae/bin/aero
cp /tmp/ae/bin/aero /usr/local/bin/aero
aero --version

echo "==> ALL DONE"
