#!/usr/bin/env bash

# Copyright (c) 2021 CloudedQuartz
# Copyright (c) 2021-2023 Diaz1401

ARG=$@
ERRORMSG="\nusage: ./build-gcc.sh argument\navailable argument:\n  lto, enable LTO GCC\n  pgo, enable Profile Guided Optimization\n  gcov, enable gcov profiling\n  stable, latest Release GCC\n  stable-TAG, spesific Release GCC tag\n  beta, latest Bleeding Edge GCC\n  beta-TAG, spesific Bleeding Edge GCC tag\n\nvalid GCC tag:\n  https://github.com/Diaz1401/gcc-stable/releases\n  https://github.com/Diaz1401/gcc/releases\n"
if [ -z "$ARG" ]; then
  echo -e $ERRORMSG
  exit 1
else
  for i in ${ARG}; do
    case "${i}" in
      lto) LTO=true;;
      pgo) PGO=true;;
      gcov) GCOV=true;;
      stable) STABLE=true;;
      stable-*) STABLE=$(echo "${i}" | sed s/stable-//g);;
      beta) BETA=true;;
      beta-*) BETA=$(echo "${i}" | sed s/beta-//g);;
      *) echo -e $ERRORMSG; exit 1;;
    esac
  done
  if [ ! -z "${PGO}" ] && [ ! -z "${GCOV}" ]; then
    echo "do not use both gcov and pgo"
    exit 1
  elif [ ! -z "${STABLE}" ] && [ ! -z "${BETA}" ]; then
    echo "do not use both GCC stable and beta"
    exit 1
  elif [ "${STABLE}" == "true" ] || [ "${BETA}" == "true" ]; then
    USE_LATEST=true
  fi
fi
export LTO PGO GCOV STABLE BETA USE_LATEST

# Silence all safe.directory warnings
git config --global --add safe.directory '*'

export KERNEL_NAME=Kucing
export KERNEL_DIR=$(pwd)
export AK3=${KERNEL_DIR}/AnyKernel3
export TOOLCHAIN=${KERNEL_DIR}/gcc
export LOG=${KERNEL_DIR}/log.txt
export KERNEL_DTB=${KERNEL_DIR}/out/arch/arm64/boot/dtb
export KERNEL_IMG=${KERNEL_DIR}/out/arch/arm64/boot/Image
export KERNEL_IMG_DTB=${KERNEL_DIR}/out/arch/arm64/boot/Image-dtb
export KERNEL_IMG_GZ_DTB=${KERNEL_DIR}/out/arch/arm64/boot/Image.gz-dtb
export KERNEL_DTBO=${KERNEL_DIR}/out/arch/arm64/boot/dtbo.img
export TG_CHAT_ID=-1001180467256
export TG_BOT_TOKEN=${TELEGRAM_TOKEN}
export DATE_NAME=$(date +"%Y%m%d")
export COMMIT=$(git log --pretty=format:"%s" -1)
export COMMIT_SHA=$(git rev-parse --short HEAD)
export KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
export BUILD_DATE=$(date)
export KBUILD_BUILD_USER=Diaz
export PATH="${TOOLCHAIN}/bin:${PATH}"

# Colors
export WHITE='\033[0m'
export RED='\033[1;31m'
export GREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[1;34m'

#
# Clone GCC Compiler
clone_tc(){
  if [[ -a ${TOOLCHAIN} ]]; then
    echo -e "${YELLOW}===> ${BLUE}CAT GCC exist${WHITE}"
  else
    echo -e "${YELLOW}===> ${BLUE}Downloading CAT GCC${WHITE}"
    mkdir -p ${TOOLCHAIN}
    if [ "${USE_LATEST}" == "true" ]; then
      if [ ! -z "${STABLE}" ]; then
        curl -s https://api.github.com/repos/Diaz1401/gcc-stable/releases/latest | grep "browser_download_url" | cut -d '"' -f4 | wget -qO gcc.tar.zst -i -
      else
        curl -s https://api.github.com/repos/Diaz1401/gcc/releases/latest | grep "browser_download_url" | cut -d '"' -f4 | wget -qO gcc.tar.zst -i -
      fi
    else
      if [ ! -z "${STABLE}" ]; then
        wget -qO gcc.tar.zst https://github.com/Diaz1401/gcc-stable/releases/download/${STABLE}/gcc.tar.zst
      else
        wget -qO gcc.tar.zst https://github.com/Diaz1401/gcc/releases/download/${BETA}/gcc.tar.zst
      fi
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
# send_info - sends text to telegram
send_info(){
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
    -F chat_id="${TG_CHAT_ID}" > /dev/null 2>&1
}

#
# send_file - uploads file to telegram
send_file(){
  curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
    -F chat_id=$TG_CHAT_ID \
    -F caption="$2" \
    -F parse_mode=html > /dev/null 2>&1
}

#
# send_file_nocap - uploads file to telegram without caption
send_file_nocap(){
  curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
    -F chat_id=$TG_CHAT_ID \
    -F parse_mode=html > /dev/null 2>&1
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
#  rm -rf out
#  mkdir -p out
  if [[ $1 == miui ]]; then
    miui_patch
  fi
  BUILD_START=$(date +"%s")
  if [ "$LTO" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e LTO_GCC
  elif [ "$GCOV" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e GCOV_KERNEL -e GCOV_PROFILE_ALL
  elif [ "$PGO" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e PGO
  fi
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
    send_file $LOG "$ZIP_NAME log"
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
  ZIP_NAME=${KERNEL_NAME}-${DATE_NAME}-${COMMIT_SHA}.zip
  if [ "${LTO}" == "true" ]; then
    ZIP_NAME=LTO-${ZIP_NAME}
  elif [ "${PGO}" == "true" ]; then
    ZIP_NAME=PGO-${ZIP_NAME}
  elif [ "${GCOV}" == "true" ]; then
    ZIP_NAME=GCOV-${ZIP_NAME}
  elif [ "${1}" == "miui" ]; then
    ZIP_NAME=MIUI-${ZIP_NAME}
  fi
  zip -r9 ${ZIP_NAME} * -x .git .github LICENSE README.md
  mv ${KERNEL_DTBO} ${AK3}/${DTBO_NAME}
  mv ${KERNEL_DTB} ${AK3}/${DTB_NAME}
  echo -e "${YELLOW}===> ${BLUE}Send kernel to Telegram${WHITE}"
  send_file ${ZIP_NAME} "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
  echo -e "${YELLOW}===> ${WHITE}Zip name: ${GREEN}${ZIP_NAME}"
  send_file ${KERNEL_DIR}/out/.config "$ZIP_NAME defconfig"
#  echo -e "${YELLOW}===> ${BLUE}Send dtbo.img to Telegram${WHITE}"
#  send_file ${DTBO_NAME}
#  echo -e "${YELLOW}===> ${BLUE}Send dtb to Telegram${WHITE}"
#  send_file ${DTB_NAME}
#  echo -e "${YELLOW}===> ${RED}Send build log to Telegram${WHITE}"
  send_file $LOG "$ZIP_NAME log"
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
  send_info ${FLAG}
  build_kernel ${FLAG}
  build_end ${FLAG}
}

#
# compile time
clone_tc
clone_ak
build_all
#build_all miui
