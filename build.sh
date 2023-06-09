#!/usr/bin/env bash

# Copyright (c) 2021 CloudedQuartz
# Copyright (c) 2021-2023 Diaz1401

ARG=$@
ERRORMSG="\
Usage: ./build-gcc.sh argument\n\
Available argument:\n\
  clang           use LLVM Clang\n\
  gcc             use GCC\n\
  opt             enable cat_optimize\n\
  lto             enable LTO\n\
  pgo             enable PGO\n\
  dce             enable dead code and data elimination\n\
  gcov            enable gcov profiling\n\
  beta            download experimental toolchain\n\
  stable          download stable toolchain (only GCC for now)\n\
  beta-TAG        spesific experimental toolchain tag\n\
  stable-TAG      spesific stable toolchain tag\n\n\
valid stable toolchain tag:\n\
  https://github.com/Diaz1401/gcc-stable/releases\n\n\
valid experimental toolchain tag:\n\
  https://github.com/Diaz1401/clang/releases\n\
  https://github.com/Diaz1401/gcc/releases"

if [ -z "$ARG" ]; then
  echo -e "$ERRORMSG"
  exit 1
else
  for i in $ARG; do
    case "$i" in
      clang) CLANG=true;;
      gcc) GCC=true;;
      opt) CAT=true;;
      lto) LTO=true;;
      pgo) PGO=true;;
      dce) DCE=true;;
      gcov) GCOV=true;;
      beta) BETA=true;;
      stable) STABLE=true;;
      beta-*) BETA=$(echo "$i" | sed s/beta-//g);;
      stable-*) STABLE=$(echo "$i" | sed s/stable-//g);;
      *) echo -e "$ERRORMSG"; exit 1;;
    esac
  done
  if [ -z "$GCC" ] && [ -z "$CLANG" ]; then
    echo "toolchain not specified"
    exit 1; fi
  if [ ! -z "$GCC" ] && [ ! -z "$CLANG" ]; then
    echo "do not use both gcc and clang"
    exit 1; fi
  if [ ! -z "$PGO" ] && [ ! -z "$GCOV" ]; then
    echo "do not use both gcov and pgo"
    exit 1; fi
  if [ -z "$STABLE" ] && [ -z "$BETA" ]; then
    echo "specify stable or beta"
    exit 1; fi
  if [ ! -z "$STABLE" ] && [ ! -z "$BETA" ]; then
    echo "do not use both stable and beta"
    exit 1; fi
  if [ "$STABLE" == "true" ] || [ "$BETA" == "true" ]; then
    USE_LATEST=true
  fi
fi

# Silence all safe.directory warnings
git config --global --add safe.directory '*'

KERNEL_NAME=Kucing
KERNEL_DIR=$(pwd)
{NPROC}=$(nproc --all)
AK3=${KERNEL_DIR}/AnyKernel3
TOOLCHAIN=${KERNEL_DIR}/toolchain
LOG=${KERNEL_DIR}/log.txt
KERNEL_DTB=${KERNEL_DIR}/out/arch/arm64/boot/dtb
KERNEL_IMG=${KERNEL_DIR}/out/arch/arm64/boot/Image
KERNEL_IMG_DTB=${KERNEL_DIR}/out/arch/arm64/boot/Image-dtb
KERNEL_IMG_GZ_DTB=${KERNEL_DIR}/out/arch/arm64/boot/Image.gz-dtb
KERNEL_DTBO=${KERNEL_DIR}/out/arch/arm64/boot/dtbo.img
TELEGRAM_CHAT=-1001180467256
#unused TELEGRAM_TOKEN=${TELEGRAM_TOKEN}
DATE=$(date +"%Y%m%d")
COMMIT=$(git log --pretty=format:"%s" -1)
COMMIT_SHA=$(git rev-parse --short HEAD)
KERNEL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BUILD_DATE=$(date)
KBUILD_BUILD_USER=Diaz
PATH=${TOOLCHAIN}/bin:${PATH}
# Colors
WHITE='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'

export {NPROC} KERNEL_NAME KERNEL_DIR AK3 TOOLCHAIN LOG KERNEL_DTB KERNEL_IMG KERNEL_IMG_DTB KERNEL_IMG_GZ_DTB KERNEL_DTBO TELEGRAM_CHAT DATE COMMIT COMMIT_SHA KERNEL_BRANCH BUILD_DATE KBUILD_BUILD_USER PATH WHITE RED GREEN YELLOW BLUE CLANG GCC CAT LTO PGO GCOV STABLE BETA USE_LATEST

#
# Clone Toolchain
clone_tc(){
  if [ -a "$TOOLCHAIN" ]; then
    echo -e "${YELLOW}===> ${BLUE}Toolchain exist${WHITE}"
  else
    echo -e "${YELLOW}===> ${BLUE}Downloading Toolchain${WHITE}"
    mkdir -p "$TOOLCHAIN"
    if [ "$GCC" == "true" ]; then
      if [ "$USE_LATEST" == "true" ]; then
        if [ ! -z "$STABLE" ]; then
          curl -s https://api.github.com/repos/Diaz1401/gcc-stable/releases/latest | grep "browser_download_url" | cut -d '"' -f4 | wget -qO gcc.tar.zst -i -
        else
          curl -s https://api.github.com/repos/Diaz1401/gcc/releases/latest | grep "browser_download_url" | cut -d '"' -f4 | wget -qO gcc.tar.zst -i -
        fi
      else
        if [ ! -z "$STABLE" ]; then
          wget -qO gcc.tar.zst https://github.com/Diaz1401/gcc-stable/releases/download/${STABLE}/gcc.tar.zst
        else
          wget -qO gcc.tar.zst https://github.com/Diaz1401/gcc/releases/download/${BETA}/gcc.tar.zst
        fi
      fi
      tar xf gcc.tar.zst -C $TOOLCHAIN
    else
      if [ "$USE_LATEST" == "true" ]; then
        curl -s https://api.github.com/repos/Diaz1401/clang/releases/latest |
          grep "browser_download_url" |
          cut -d '"' -f4 |
          wget -qO clang.tar.zst -i -
      elif [ ! -z "$BETA" ]; then
        wget -qO clang.tar.zst https://github.com/Diaz1401/clang/releases/download/${BETA}/clang.tar.zst
      else
        echo "specify beta-TAG when using clang, stable-TAG not supported"
        exit 1
      fi
      tar xf clang.tar.zst -C $TOOLCHAIN
    fi
  fi
}

#
# Clones anykernel
clone_ak(){
  if [ -a "$AK3" ]; then
    echo -e "${YELLOW}===> ${BLUE}AnyKernel3 exist${WHITE}"
    echo -e "${YELLOW}===> ${BLUE}Try to update repo${WHITE}"
    cd $AK3
    git pull
    cd -
  else
    echo -e "${YELLOW}===> ${BLUE}Cloning AnyKernel3${WHITE}"
    git clone -q --depth=1 -b alioth https://github.com/Diaz1401/AnyKernel3.git $AK3
  fi
}

#
# send_info - sends text to telegram
send_info(){
  if [ "$1" == "miui" ]; then
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
  curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -F parse_mode=html \
    -F text="$CAPTION" \
    -F chat_id="$TELEGRAM_CHAT" > /dev/null 2>&1
}

#
# send_file - uploads file to telegram
send_file(){
  curl -F document=@"$1"  "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT" \
    -F caption="$2" \
    -F parse_mode=html > /dev/null 2>&1
}

#
# send_file_nocap - uploads file to telegram without caption
send_file_nocap(){
  curl -F document=@"$1"  "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT" \
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
  cd $KERNEL_DIR
#  rm -rf out
#  mkdir -p out
  if [ "$1" == "miui" ]; then
    miui_patch
  fi
  BUILD_START=$(date +"%s")
  if [ "$CAT" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e CAT_OPTIMIZE; fi
  if [ "$LTO" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e LTO_GCC; fi
  if [ "$GCOV" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e GCOV_KERNEL -e GCOV_PROFILE_ALL; fi
  if [ "$PGO" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e PGO; fi
  if [ "$PGO" == "true" ]; then
    ./scripts/config --file arch/arm64/configs/cat_defconfig -e LD_DEAD_CODE_DATA_ELIMINATION; fi
  if [ "$GCC" == "true" ]; then
    make -j${NPROC} O=out cat_defconfig CROSS_COMPILE=aarch64-elf- |& tee -a $LOG
    make -j${NPROC} O=out CROSS_COMPILE=aarch64-elf- |& tee -a $LOG
  else
    make -j${NPROC} O=out cat_defconfig LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- |& tee -a $LOG
    make -j${NPROC} O=out LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- |& tee -a $LOG
  fi
  BUILD_END=$(date +"%s")
  DIFF=$((BUILD_END - BUILD_START))
}

#
# build_end - creates and sends zip
build_end(){
  rm -rf ${AK3}/Kucing* ${AK3}/MIUI-Kucing* ${AK3}/dtb* ${AK3}/Image*
  if [ -a "$KERNEL_IMG_GZ_DTB" ]; then
    mv $KERNEL_IMG_GZ_DTB $AK3
  elif [ -a "$KERNEL_IMG_DTB" ]; then
    mv $KERNEL_IMG_DTB $AK3
  elif [ -a "$KERNEL_IMG" ]; then
    mv $KERNEL_IMG $AK3
  else
    echo -e "${YELLOW}===> ${RED}Build failed, sad${WHITE}"
    echo -e "${YELLOW}===> ${GREEN}Send build log to Telegram${WHITE}"
    send_file $LOG "$ZIP_NAME log"
    exit 1
  fi
  echo -e "${YELLOW}===> ${GREEN}Build success, generating flashable zip...${WHITE}"
  find ${KERNEL_DIR}/out/arch/arm64/boot/dts/vendor/qcom -name '*.dtb' -exec cat {} + > $KERNEL_DTB
  ls ${KERNEL_DIR}/out/arch/arm64/boot/
  cp $KERNEL_DTBO $AK3
  cp $KERNEL_DTB $AK3
  cd $AK3
  DTBO_NAME=${KERNEL_NAME}-DTBO-${DATE}-${COMMIT_SHA}.img
  DTB_NAME=${KERNEL_NAME}-DTB-${DATE}-${COMMIT_SHA}
  ZIP_NAME=${KERNEL_NAME}-${DATE}-${COMMIT_SHA}.zip
  if [ "$CLANG" == "true" ]; then
    ZIP_NAME=CLANG-${ZIP_NAME}; fi
  if [ "$GCC" == "true" ]; then
    ZIP_NAME=GCC-${ZIP_NAME}; fi
  if [ "$CAT" == "true" ]; then
    ZIP_NAME=OPT-${ZIP_NAME}; fi
  if [ "$LTO" == "true" ]; then
    ZIP_NAME=LTO-${ZIP_NAME}; fi
  if [ "$PGO" == "true" ]; then
    ZIP_NAME=PGO-${ZIP_NAME}; fi
  if [ "$GCOV" == "true" ]; then
    ZIP_NAME=GCOV-${ZIP_NAME}; fi
  if [ "$1" == "miui" ]; then
    ZIP_NAME=MIUI-${ZIP_NAME}; fi
  zip -r9 $ZIP_NAME * -x .git .github LICENSE README.md
  mv $KERNEL_DTBO ${AK3}/${DTBO_NAME}
  mv $KERNEL_DTB ${AK3}/${DTB_NAME}
  echo -e "${YELLOW}===> ${BLUE}Send kernel to Telegram${WHITE}"
  send_file $ZIP_NAME "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
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
  send_info $FLAG
  build_kernel $FLAG
  build_end $FLAG
}

#
# compile time
clone_tc
clone_ak
build_all
#build_all miui
