#!/bin/bash

# Copyright (c) 2021 CloudedQuartz
# Copyright (c) 2021 Diaz1401

KERNEL_NAME="Kucing"
KERNEL_DIR="$(pwd)"
AK3="$KERNEL_DIR/AnyKernel3"
TOOLCHAIN="$KERNEL_DIR/clang"
LOG="$KERNEL_DIR/log.txt"
KERNEL_IMG="$KERNEL_DIR/out/arch/arm64/boot/Image"
KERNEL_DTBO="$KERNEL_DIR/out/arch/arm64/boot/dtbo.img"
TG_CHAT_ID="-1001180467256"
TG_BOT_TOKEN="$TELEGRAM_TOKEN"
CLANG_VERSION="r437112"

# Colors
WHITE='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'

export KBUILD_BUILD_USER="Diaz"
export KBUILD_BUILD_HOST="DroneCI"
export PATH="$TOOLCHAIN/bin:$TOOLCHAIN/arm64/bin:$TOOLCHAIN/arm/bin:$PATH"

#
# Clone Clang Compiler
clone_tc() {
	mkdir -p $TOOLCHAIN && cd $TOOLCHAIN
	echo -e "${YELLOW}===> ${BLUE}Downloading AOSP Clang ${CLANG_VERSION}${WHITE}"
	wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-$CLANG_VERSION.tar.gz
	tar -xf clang*
	echo -e "${YELLOW}===> ${BLUE}Cloning GCC Cross Compiler${WHITE}"
	git clone -q https://github.com/Diaz1401/gcc-arm64 --depth 1 -b gcc-11 $TOOLCHAIN/arm64
	git clone -q https://github.com/Diaz1401/gcc-arm --depth 1 -b gcc-11 $TOOLCHAIN/arm

}

#
# Clones anykernel
clone_ak() {
    echo -e "${YELLOW}===> ${BLUE}Cloning AnyKernel3${WHITE}"
    git clone -q --depth 1 https://github.com/Diaz1401/AnyKernel3.git -b alioth $AK3
}

#
# tg_sendinfo - sends text to telegram
tg_sendinfo() {
        curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
                -F parse_mode=html \
                -F text="${1}" \
                -F chat_id="${TG_CHAT_ID}" &> /dev/null
}

#
# tg_pushzip - uploads final zip to telegram
tg_pushzip() {
        curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
                        -F chat_id=$TG_CHAT_ID \
                        -F caption="$2" \
                        -F parse_mode=html &> /dev/null
}

#
# tg_log - uploads build log to telegram
tg_log() {
    curl -F document=@"$LOG"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F parse_mode=html &> /dev/null
}

#
# build_kernel
build_kernel() {
    cd "$KERNEL_DIR"
    rm -rf out
    mkdir out
    BUILD_START=$(date +"%s")
    export KBUILD_COMPILER_STRING=$("$TOOLCHAIN"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
    make O=out cat_defconfig LLVM=1
    make -j$(nproc --all) O=out \
       LLVM=1 \
       CROSS_COMPILE=aarch64-elf- \
       CROSS_COMPILE_ARM32=arm-eabi- |& tee $LOG

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
    DATE_NAME=$(date +"%A"_"%I":"%M"_"%p")
}

#
# build_end - creates and sends zip
build_end() {

    if ! [[ -a "$KERNEL_IMG" && -a "$KERNEL_DTBO" ]]; then
    echo -e "${YELLOW}===> ${RED}Build failed, sad${WHITE}"
    echo -e "${YELLOW}===> ${GREEN}Send build log to Telegram${WHITE}"
    tg_log
    exit 1
    fi

    echo -e "${YELLOW}===> ${GREEN}Build success, generating flashable zip..."
    cd $AK3
    mv "$KERNEL_IMG" "$AK3"
    mv "$KERNEL_DTBO" "$AK3"
    ZIP_NAME=$KERNEL_NAME-$DATE_NAME
    zip -r9 "$ZIP_NAME".zip * -x .git README.md
    ZIP_NAME="$ZIP_NAME".zip

    echo -e "${YELLOW}===> ${BLUE}Send zip to Telegram"
    tg_pushzip "$ZIP_NAME" "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
    echo -e "${YELLOW}===> ${WHITE}Zip name: ${GREEN}${ZIP_NAME}"
    echo -e "${YELLOW}===> ${RED}Send build log to Telegram"
    tg_log
}

COMMIT=$(git log --pretty=format:"%s" -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BUILD_DATE=$(date)
CAPTION=$(echo -e \
"Build started
Date: <code>$BUILD_DATE</code>
HEAD: <code>$COMMIT_SHA</code>
Commit: <code>$COMMIT</code>
Branch: <code>$KERNEL_BRANCH</code>
")

#
# compile time
clone_tc
clone_ak
tg_sendinfo "$CAPTION
"
build_kernel
build_end
