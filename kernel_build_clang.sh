#! /bin/bash
# Copyright (C) 2020 KenHV
# Copyright (C) 2020 Starlight
# Copyright (C) 2021 CloudedQuartz
#

# Config
DEVICE="beryllium"
DEFCONFIG="${DEVICE}_lto_defconfig"
LOG="$HOME/log.txt"
BUILD_DATE=$(date +"%A"_"%I":"%M"_"%p")
# Export arch and subarch
ARCH="arm64"
SUBARCH="arm64"
export ARCH SUBARCH

KERNEL_IMG=$KERNEL_DIR/out/arch/$ARCH/boot/Image.gz-dtb

TG_CHAT_ID="942627647"
TG_BOT_TOKEN="$(cat $KERNEL_DIR/key.txt)"
# End config

# Function definitions

# tg_sendinfo - sends text through telegram
tg_sendinfo() {
	curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
		-F parse_mode=html \
		-F text="${1}" \
		-F chat_id="${TG_CHAT_ID}" &> /dev/null
}

# tg_pushzip - uploads final zip to telegram
tg_pushzip() {
	curl -F document=@"$1"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
			-F chat_id=$TG_CHAT_ID \
			-F caption="$2" \
			-F parse_mode=html &> /dev/null
}

# tg_failed - uploads build log to telegram
tg_failed() {
    curl -F document=@"$LOG"  "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
        -F chat_id=$TG_CHAT_ID \
        -F parse_mode=html &> /dev/null
}

# build_setup - enter kernel directory and get info for caption.
# also removes the previous kernel image, if one exists.
build_setup() {
    cd "$KERNEL_DIR" || echo -e "\nKernel directory ($KERNEL_DIR) does not exist" || exit 1

    [[ ! -d out ]] && mkdir out
    [[ -f "$KERNEL_IMG" ]] && rm "$KERNEL_IMG"
	find . -name "*.dtb" -type f -delete
}

# build_config - builds .config file for device.
build_config() {
	make O=out $1 -j$(nproc --all)
}
# build_kernel - builds defconfig and kernel image using llvm tools, while saving the output to a specified log location
# only use after runing build_setup()
build_kernel() {

    BUILD_START=$(date +"%s")
    make -j$(nproc --all) O=out \
                PATH="$TC_DIR/bin:$PATH" \
                CC="clang" \
                CROSS_COMPILE=$TC_DIR/bin/aarch64-linux-gnu- \
                CROSS_COMPILE_ARM32=$TC_DIR/bin/arm-linux-gnueabi- \
                LLVM=llvm- \
                AR=llvm-ar \
                NM=llvm-nm \
                OBJCOPY=llvm-objcopy \
                OBJDUMP=llvm-objdump \
                STRIP=llvm-strip |& tee $LOG

    BUILD_END=$(date +"%s")
    DIFF=$((BUILD_END - BUILD_START))
}

# build_end - creates and sends zip
build_end() {

	if ! [ -a "$KERNEL_IMG" ]; then
        echo -e "\n> Build failed, sending logs to Telegram."
        tg_failed
        tg_buildtime
        exit 1
    fi

    echo -e "\n> Build successful! generating flashable zip..."
	cd "$AK_DIR" || echo -e "\nAnykernel directory ($AK_DIR) does not exist" || exit 1
	git clean -fd
	mv "$KERNEL_IMG" "$AK_DIR"/zImage
	ZIP_NAME=$KERNELNAME-GCC-LTO-$BUILD_DATE
	zip -r9 "$ZIP_NAME".zip ./* -x .git README.md ./*placeholder
        ZIP_NAME="$ZIP_NAME".zip

	tg_pushzip "$ZIP_NAME" "Time taken: <code>$((DIFF / 60))m $((DIFF % 60))s</code>"
	echo -e "\n> Sent zip through Telegram.\n> File: $ZIP_NAME"
}

tg_sendinfo "-- Build Triggered --
"

# Build old touch fw version for device 1
# Build device 1
build_setup
build_config $DEFCONFIG
build_kernel
build_end





BUILD_START=$(date +"%s")
    make -j$(nproc --all) O=out \
                PATH="$TC_DIR/bin:$PATH" \
                CC="clang" \
                CROSS_COMPILE=$TC_DIR/bin/aarch64-linux-gnu- \
                CROSS_COMPILE_ARM32=$TC_DIR/bin/arm-linux-gnueabi- \
                LLVM=llvm- \
                AR=llvm-ar \
                NM=llvm-nm \
                OBJCOPY=llvm-objcopy \
                OBJDUMP=llvm-objdump \
                STRIP=llvm-strip |& tee $LOG
