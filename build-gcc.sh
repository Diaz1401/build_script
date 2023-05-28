#!/bin/bash

# Copyright (c) 2021 CloudedQuartz
# Copyright (c) 2021-2022 Diaz1401

# Silence all safe.directory warnings
git config --global --add safe.directory '*'

KERNEL_NAME=Kucing
KERNEL_DIR=$(pwd)
AK3=${KERNEL_DIR}/AnyKernel3
TOOLCHAIN=${KERNEL_DIR}/gcc
LOG=${KERNEL_DIR}/log.txt
KERNEL_DTB=${KERNEL_DIR}/out/arch/arm64/boot/dtb
KERNEL_IMG=${KERNEL_DIR}/out/arch/arm64/boot/Image
KERNEL_IMG_DTB=${KERNEL_DIR}/out/arch/arm64/boot/Image-dtb
KERNEL_IMG_GZ_DTB=${KERNEL_DIR}/out/arch/arm64/boot/Image.gz-dtb
KERNEL_DTBO=${KERNEL_DIR}/out/arch/arm64/boot/dtbo.img
TG_CHAT_ID=-1001180467256
TG_BOT_TOKEN=${TELEGRAM_TOKEN}
DATE_NAME=$(date +"%Y%m%d")
COMMIT=$(git log --pretty=format:"%s" -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BUILD_DATE=$(date)

GCC_VERSION=${1}

# Colors
WHITE='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'

export KBUILD_BUILD_USER=Diaz
export PATH="${TOOLCHAIN}/bin:${PATH}"

#
# Clone GCC Compiler
clone_tc(){
    if [[ -a ${TOOLCHAIN} ]]; then
        echo -e "${YELLOW}===> ${BLUE}CAT GCC exist${WHITE}"
    else
        echo -e "${YELLOW}===> ${BLUE}Downloading CAT GCC${WHITE}"
        mkdir -p ${TOOLCHAIN}
        if [ -z ${GCC_VERSION} ]; then
            curl -s https://api.github.com/repos/Diaz1401/gcc/releases/latest |
                grep "browser_download_url" |
                cut -d '"' -f4 |
                wget -qO gcc.tar.zst -i -
        else
            wget -qO gcc.tar.zst https://github.com/Diaz1401/gcc/releases/download/${GCC_VERSION}/gcc.tar.zst
        fi
        tar xf gcc.tar.zst -C ${TOOLCHAIN}
    fi
}

#
# Clones anykernel
clone_ak(){
    if [[ -a ${AK3} ]]; then
        echo -e "${YELLOW}===> ${BLUE}AnyKernel3 exist${WHITE}"
        echo -e "${YELLOW}===> ${BLUE}Try to update repo${WHITE}"
        pushd ${AK3}
        git pull
        popd
    else
        echo -e "${YELLOW}===> ${BLUE}Cloning AnyKernel3${WHITE}"
        git clone -q --depth 1 https://github.com/Diaz1401/AnyKernel3.git -b alioth ${AK3}
    fi
}

#
# tg_sendinfo - sends text to telegram
tg_sendinfo(){
    if [[ $1 == miui ]]; then
        CAPTION=$(echo -e \
        "MIUI Build started
Date: <code>${BUILD_DATE}</code>
HEAD: <code>${COMMIT_SHA}</code>
Commit: <code>${COMMIT}</code>
Branch: <code>${KERNEL_BRANCH}</code>
")
    else
    CAPTION=$(echo -e \
        "Build started
Date: <code>${BUILD_DATE}</code>
HEAD: <code>${COMMIT_SHA}</code>
Commit: <code>${COMMIT}</code>
Branch: <code>${KERNEL_BRANCH}</code>
")
    fi
    curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -F parse_mode=html \
        -F text="${CAPTION}" \
        -F chat_id=${TG_CHAT_ID} &> /dev/null
}

#
# tg_pushzip - uploads final zip to telegram
tg_pushzip(){
    curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F caption="$2" \
        -F parse_mode=html &> /dev/null
}

#
# tg_log - uploads build log to telegram
tg_log(){
    curl -F document=@"$LOG"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F parse_mode=html &> /dev/null
}

#
# miui_patch - apply custom patch before build
miui_patch(){
    git apply patch/miui-panel-dimension.patch
}

#
# build_kernel
build_kernel(){
    cd ${KERNEL_DIR}
    rm -rf out
    mkdir -p out
    if [[ $1 == miui ]]; then
        miui_patch
    fi
    BUILD_START=$(date +"%s")
    make O=out cat_defconfig
    make -j$(nproc --all) O=out \
        CROSS_COMPILE=aarch64-elf- |& tee $LOG
    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
}

#
# build_end - creates and sends zip
build_end(){
    rm -rf ${AK3}/Kucing* ${AK3}/MIUI-Kucing* ${AK3}/dtb* ${AK3}/Image*
    if [[ -a ${KERNEL_IMG_GZ_DTB} ]]; then
        mv ${KERNEL_IMG_GZ_DTB} ${AK3}
    elif [[ -a {$KERNEL_IMG_DTB} ]]; then
        mv ${KERNEL_IMG_DTB} ${AK3}
    elif [[ -a ${KERNEL_IMG} ]]; then
        mv ${KERNEL_IMG} ${AK3}
    else
    echo -e "${YELLOW}===> ${RED}Build failed, sad${WHITE}"
    echo -e "${YELLOW}===> ${GREEN}Send build log to Telegram${WHITE}"
    tg_log
    exit 1
    fi
    echo -e "${YELLOW}===> ${GREEN}Build success, generating flashable zip...${WHITE}"
    find ${KERNEL_DIR}/out/arch/arm64/boot/dts/vendor/qcom -name '*.dtb' -exec cat {} + > ${KERNEL_DIR}/out/arch/arm64/boot/dtb
    ls ${KERNEL_DIR}/out/arch/arm64/boot/
    cp ${KERNEL_DTBO} ${AK3}
    cp ${KERNEL_DTB} ${AK3}
    cd ${AK3}
    DTBO_NAME=${KERNEL_NAME}-DTBO-${DATE_NAME}-${COMMIT_SHA}.img
    DTB_NAME=${KERNEL_NAME}-DTB-${DATE_NAME}-${COMMIT_SHA}
    if [[ $1 == miui ]]; then
        ZIP_NAME=MIUI-${KERNEL_NAME}-${DATE_NAME}-${COMMIT_SHA}.zip
    else
        ZIP_NAME=${KERNEL_NAME}-${DATE_NAME}-${COMMIT_SHA}.zip
    fi
    zip -r9 ${ZIP_NAME} * -x .git .github LICENSE README.md
    mv ${KERNEL_DTBO} ${AK3}/${DTBO_NAME}
    mv ${KERNEL_DTB} ${AK3}/${DTB_NAME}
    echo -e "${YELLOW}===> ${BLUE}Send kernel to Telegram${WHITE}"
    tg_pushzip ${ZIP_NAME} "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
    echo -e "${YELLOW}===> ${WHITE}Zip name: ${GREEN}${ZIP_NAME}"
    echo -e "${YELLOW}===> ${BLUE}Send dtbo.img to Telegram${WHITE}"
    tg_pushzip ${DTBO_NAME}
    echo -e "${YELLOW}===> ${BLUE}Send dtb to Telegram${WHITE}"
    tg_pushzip ${DTB_NAME}
    echo -e "${YELLOW}===> ${RED}Send build log to Telegram${WHITE}"
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
# build_all - run build script
build_all(){
    FLAG=$1
    tg_sendinfo ${FLAG}
    build_kernel ${FLAG}
    build_end ${FLAG}
}

#
# compile time
clone_tc
clone_ak
build_all
#build_all miui
