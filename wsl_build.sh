#!/bin/bash
set -e
mkdir -p /work
ln -sfn "/mnt/e/Projects/AeroProjects/Aero OS Version/AeroOS 26R1" /work/aeroos
ls /work/aeroos/
echo "==="
cd /work/aeroos/target/riscv64-qemu-virt
make clean 2>&1
echo "=== MAKE ==="
make 2>&1
echo "=== DONE ==="
ls -la /work/aeroos/build/
