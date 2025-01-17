#!/usr/bin/env bash

# Copyright (c) 2021 CloudedQuartz
# Copyright (c) 2021-2025 Diaz1401

REV="Sun 19 Jan 2025 10:18:25 WIB"

ARG=$@
ERRORMSG="\
Usage: ./build.sh argument\n\
Available argument:\n\
  local           build kernel in local machine\n\
  clang           use Clang/LLVM\n\
  aosp            use Android Clang/LLVM (use with 'clang' option)\n\
  gcc             use GCC\n\
  opt             enable cat_optimize\n\
  lto             enable LTO\n\
  pgo_gen         enable profiling\n\
  pgo_use         enable PGO\n\
  dce             enable dead code and data elimination\n\
  keep            keep toolchain\n\
  beta            download experimental toolchain\n\
  stable          download stable toolchain\n\
  beta-TAG        spesific experimental toolchain tag\n\
  stable-TAG      spesific stable toolchain tag\n\n\
valid stable toolchain tag:\n\
  https://github.com/mengkernel/clang-stable/releases\n\
  https://github.com/mengkernel/gcc-stable/releases\n\
valid experimental toolchain tag:\n\
  https://github.com/mengkernel/clang/releases\n\
  https://github.com/mengkernel/gcc/releases"

CLANG=false
AOSP=false
GCC=false
CAT=false
LTO=false
PGO_GEN=false
PGO_USE=false
DCE=false
TAG=""
BETA=false
STABLE=false
LATEST=true
KEEP=false
LOCAL=false

if [ -z "$ARG" ]; then
  echo -e "$ERRORMSG"
  exit 1
else
  for i in $ARG; do
    case "$i" in
    local) LOCAL=true ;;
    clang) CLANG=true ;;
    aosp) AOSP=true ;;
    gcc) GCC=true ;;
    opt) CAT=true ;;
    lto) LTO=true ;;
    pgo_gen) PGO_GEN=true ;;
    pgo_use) PGO_USE=true ;;
    dce) DCE=true ;;
    keep) KEEP=true ;;
    beta) BETA=true ;;
    stable) STABLE=true ;;
    beta-*) LATEST=false BETA=true TAG=$(echo "$i" | sed s/beta-//g) ;;
    stable-*) LATEST=false STABLE=true TAG=$(echo "$i" | sed s/stable-//g) ;;
    *)
      echo -e "$ERRORMSG"
      exit 1
      ;;
    esac
  done

  if ! $GCC && ! $CLANG; then
    echo "Toolchain not specified (clang/gcc)"
    exit 1
  elif $GCC && $CLANG; then
    echo "Do not use both GCC and Clang"
    exit 1
  elif $PGO_GEN && $PGO_USE; then
    echo "Do not use both PGO_GEN & PGO_USE"
    exit 1
  elif ! $STABLE && ! $BETA && ! $LOCAL; then
    echo "Specify stable or beta (beta/stable/beta-TAG/stable-TAG)"
    exit 1
  elif $STABLE && $BETA && ! $LOCAL; then
    echo "Do not use both stable and beta"
    exit 1
  elif ! $CLANG && $AOSP && ! $LOCAL; then
    echo "Do not use 'aosp' without 'clang'"
    exit 1
  fi
fi

# Silence all safe.directory warnings
git config --global --add safe.directory '*'

KERNEL_NAME=Kucing
KERNEL_DIR=$(pwd)
KERNEL_OUT_DIR=${KERNEL_DIR}/out
NPROC=$(nproc --all)
AK3=${KERNEL_DIR}/AnyKernel3
TOOLCHAIN=${KERNEL_OUT_DIR}/toolchain
LOG=${KERNEL_OUT_DIR}/log.txt
KERNEL_DTB=${KERNEL_OUT_DIR}/arch/arm64/boot/dtb
KERNEL_IMG=${KERNEL_OUT_DIR}/arch/arm64/boot/Image
KERNEL_IMG_DTB=${KERNEL_OUT_DIR}/arch/arm64/boot/Image-dtb
KERNEL_IMG_GZ_DTB=${KERNEL_OUT_DIR}/arch/arm64/boot/Image.gz-dtb
KERNEL_DTBO=${KERNEL_OUT_DIR}/arch/arm64/boot/dtbo.img
TELEGRAM_CHAT=-1001180467256
#unused TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
DATE=$(date +"%Y%m%d")
COMMIT=$(git log --pretty=format:"%s" -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BUILD_DATE=$(date)
KBUILD_BUILD_USER=Diaz
PATH=${TOOLCHAIN}/bin:${TOOLCHAIN}/aarch64-linux-gnu/bin:${PATH}
AOSP_CLANG_VERSION="clang-r522817"
# Colors
WHITE='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'

echo -e "${YELLOW}Revision ===> ${BLUE}${REV}${WHITE}"

export NPROC KERNEL_NAME KERNEL_DIR KERNEL_OUT_DIR LOCAL AK3 TOOLCHAIN LOG KERNEL_DTB KERNEL_IMG KERNEL_IMG_DTB KERNEL_IMG_GZ_DTB KERNEL_DTBO TELEGRAM_CHAT DATE COMMIT COMMIT_SHA KERNEL_BRANCH BUILD_DATE KBUILD_BUILD_USER PATH WHITE RED GREEN YELLOW BLUE CLANG GCC CAT LTO PGO_GEN PGO_USE STABLE BETA LATEST TAG

#
# Clone Toolchain
clone_tc() {
  if $KEEP; then
    echo -e "${YELLOW}===> ${BLUE}Keep existing toolchain${WHITE}"
  else
    echo -e "${YELLOW}===> ${BLUE}Removing old toolchain${WHITE}"
    rm -rf $TOOLCHAIN
  fi
  echo -e "${YELLOW}===> ${BLUE}Downloading Toolchain${WHITE}"
  mkdir -p "$TOOLCHAIN"
  if $GCC; then
    if $LATEST; then
      if $STABLE; then
        curl -s https://api.github.com/repos/mengkernel/gcc-stable/releases/latest |
          grep "browser_download_url" |
          cut -d '"' -f4 |
          wget -qO gcc.tar.zst -i -
      else
        curl -s https://api.github.com/repos/mengkernel/gcc/releases/latest |
          grep "browser_download_url" |
          cut -d '"' -f4 |
          wget -qO gcc.tar.zst -i -
      fi
    else
      if $STABLE; then
        wget -qO gcc.tar.zst https://github.com/mengkernel/gcc-stable/releases/download/${TAG}/gcc.tar.zst
      else
        wget -qO gcc.tar.zst https://github.com/mengkernel/gcc/releases/download/${TAG}/gcc.tar.zst
      fi
    fi
    tar xf gcc.tar.zst -C $TOOLCHAIN
  elif $AOSP; then
    wget -qO clang.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/${AOSP_CLANG_VERSION}.tar.gz
    tar xf clang.tar.gz -C $TOOLCHAIN
  else
    if $LATEST; then
      if $STABLE; then
        curl -s https://api.github.com/repos/mengkernel/clang-stable/releases/latest |
          grep "browser_download_url" |
          cut -d '"' -f4 |
          wget -qO clang.tar.zst -i -
      else
        curl -s https://api.github.com/repos/mengkernel/clang/releases/latest |
          grep "browser_download_url" |
          cut -d '"' -f4 |
          wget -qO clang.tar.zst -i -
      fi
    else
      if $STABLE; then
        wget -qO clang.tar.zst https://github.com/mengkernel/clang-stable/releases/download/${TAG}/clang.tar.zst
      else
        wget -qO clang.tar.zst https://github.com/mengkernel/clang/releases/download/${TAG}/clang.tar.zst
      fi
    fi
    tar xf clang.tar.zst -C $TOOLCHAIN
  fi
}

#
# Clones anykernel
clone_ak() {
  if [ -a "$AK3" ]; then
    echo -e "${YELLOW}===> ${BLUE}AnyKernel3 exist${WHITE}"
    echo -e "${YELLOW}===> ${BLUE}Try to update repo${WHITE}"
    cd $AK3
    git pull
    cd -
  else
    echo -e "${YELLOW}===> ${BLUE}Cloning AnyKernel3${WHITE}"
    git clone -q --depth=1 -b alioth https://github.com/mengkernel/AnyKernel3.git $AK3
  fi
}

#
# send_info - sends text to telegram
send_info() {
  CAPTION=$(echo -e \
    "Build started
Date: <code>${BUILD_DATE}</code>
HEAD: <code>${COMMIT_SHA}</code>
Commit: <code>${COMMIT}</code>
Branch: <code>${KERNEL_BRANCH}</code>
")
  curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -F parse_mode=html \
    -F text="$CAPTION" \
    -F chat_id="$TELEGRAM_CHAT" >/dev/null 2>&1
}

#
# send_file - uploads file to telegram
send_file() {
  curl -F document=@"$1" "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT" \
    -F caption="$2" \
    -F parse_mode=html >/dev/null 2>&1
}

#
# send_files - uploads multiple files to telegram in one message
send_files() {
  i=1
  for files in $@; do
    if [ $i -eq 1 ]; then
      attach="{\"type\": \"document\", \"media\": \"attach://file$i\"}"
      arg="-F file$i=@$files"
    else
      attach="$attach, {\"type\": \"document\", \"media\": \"attach://file$i\"}"
      arg="$arg -F file$i=@$files"
    fi
    ((i++))
  done
  curl "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMediaGroup" \
    -F chat_id="$TELEGRAM_CHAT" \
    -F "media=[$attach]" \
    $arg >/dev/null 2>&1
}

#
# build_kernel
build_kernel() {
  cd $KERNEL_DIR
  BUILD_START=$(date +"%s")
  if $LTO; then
    if $GCC; then
      ./scripts/config --file arch/arm64/configs/cat_defconfig -d LTO_CLANG -e LTO_GCC
    else
      ./scripts/config --file arch/arm64/configs/cat_defconfig -d LTO_GCC -e LTO_CLANG
    fi
  fi
  if $CAT; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e CAT_OPTIMIZE
  fi
  if $PGO_GEN; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -d PGO_USE -e PGO_GEN
  fi
  if $PGO_USE; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -d PGO_GEN -e PGO_USE
  fi
  if $DCE; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e LD_DEAD_CODE_DATA_ELIMINATION
  fi
  if $GCC; then
    make -j${NPROC} O=${KERNEL_OUT_DIR} cat_defconfig CROSS_COMPILE=aarch64-linux-gnu- |& tee -a $LOG
    make -j${NPROC} O=${KERNEL_OUT_DIR} CROSS_COMPILE=aarch64-linux-gnu- |& tee -a $LOG
  else
    make -j${NPROC} O=${KERNEL_OUT_DIR} cat_defconfig LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- |& tee -a $LOG
    make -j${NPROC} O=${KERNEL_OUT_DIR} LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- |& tee -a $LOG
  fi
  BUILD_END=$(date +"%s")
  DIFF=$((BUILD_END - BUILD_START))
  if $LOCAL && [ -a $AK3 ]; then
    rm -rf ${AK3}/*.zip ${AK3}/dtb* ${AK3}/Image*
    find ${KERNEL_OUT_DIR}/arch/arm64/boot/dts/vendor/qcom -name '*.dtb' -exec cat {} + >$KERNEL_DTB
    cp ${KERNEL_IMG}* $AK3
    cp $KERNEL_DTBO $AK3
    cp $KERNEL_DTB $AK3
    cd $AK3
    zip -r9 KERNEL-TEST * -x .git* LICENSE README.md
    echo -e "${YELLOW}===> ${GREEN}Zip file created at ${AK3}/KERNEL-TEST.zip${WHITE}"
  fi
}

#
# build_end - creates and sends zip
build_end() {
  rm -rf ${AK3}/*.zip ${AK3}/dtb* ${AK3}/Image*
  if [ -a "$KERNEL_IMG_GZ_DTB" ]; then
    mv $KERNEL_IMG_GZ_DTB $AK3
  elif [ -a "$KERNEL_IMG_DTB" ]; then
    mv $KERNEL_IMG_DTB $AK3
  elif [ -a "$KERNEL_IMG" ]; then
    mv $KERNEL_IMG $AK3
  else
    echo -e "${YELLOW}===> ${RED}Build failed, sad${WHITE}"
    echo -e "${YELLOW}===> ${GREEN}Send build log to Telegram${WHITE}"
    send_files $LOG
    exit 1
  fi
  echo -e "${YELLOW}===> ${GREEN}Build success, generating flashable zip...${WHITE}"
  find ${KERNEL_OUT_DIR}/arch/arm64/boot/dts/vendor/qcom -name '*.dtb' -exec cat {} + >$KERNEL_DTB
  ls ${KERNEL_OUT_DIR}/arch/arm64/boot/
  cp $KERNEL_DTBO $AK3
  cp $KERNEL_DTB $AK3
  cd $AK3
  DTBO_NAME=${KERNEL_NAME}-DTBO-${DATE}-${COMMIT_SHA}.img
  DTB_NAME=${KERNEL_NAME}-DTB-${DATE}-${COMMIT_SHA}
  ZIP_NAME=${KERNEL_NAME}-${DATE}-${COMMIT_SHA}.zip
  if $CLANG; then
    ZIP_NAME=CLANG-${ZIP_NAME}
  fi
  if $GCC; then
    ZIP_NAME=GCC-${ZIP_NAME}
  fi
  if $CAT; then
    ZIP_NAME=OPT-${ZIP_NAME}
  fi
  if $LTO; then
    ZIP_NAME=LTO-${ZIP_NAME}
  fi
  if $DCE; then
    ZIP_NAME=DCE-${ZIP_NAME}
  fi
  if $PGO_GEN; then
    ZIP_NAME=PGO_GEN-${ZIP_NAME}
  fi
  if $PGO_USE; then
    ZIP_NAME=PGO_USE-${ZIP_NAME}
  fi
  zip -r9 KERNEL-$ZIP_NAME * -x .git .github LICENSE README.md dtb*
  zip -r9 DTBO-$ZIP_NAME * -x .git .github LICENSE README.md *Image* *.zip
  echo -e "${YELLOW}===> ${BLUE}Send kernel to Telegram${WHITE}"
  send_file KERNEL-$ZIP_NAME "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
  echo -e "${YELLOW}===> ${WHITE}Zip name: ${GREEN}${ZIP_NAME}"
  send_files DTBO-$ZIP_NAME $LOG ${KERNEL_OUT_DIR}/.config
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
build_all() {
  if ! $LOCAL; then
    send_info
  fi
  build_kernel
  if ! $LOCAL; then
    build_end
  fi
}

#
# compile time
if ! $LOCAL; then
  clone_tc
  clone_ak
fi
build_all
