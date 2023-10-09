#!/bin/bash
set -e

TRY_ID="$1"
STDOUT_TIMEOUT=60
QEMU_TXT=qemu.txt

FLAG="kernelCTF{$(uuidgen)}"
#echo "::add-mask::$FLAG"
echo $FLAG > flag

STOP_MARKER=$(uuidgen)
echo "::stop-commands::$STOP_MARKER"

touch $QEMU_TXT

START_TIME=$(date +%s)

CMDLINE="console=ttyS0 root=/dev/vda1 rootfstype=ext4 rootflags=discard ro init=/init hostname=repro"
if echo $EXPLOIT_INFO | jq -e '.requires_separate_kaslr_leak'; then CMDLINE="$CMDLINE -- kaslr_leak=1"; fi

expect -c '
    set timeout -1
    set stty_init raw

    spawn qemu-system-x86_64 -m 3.5G -nographic \
    -monitor none \
    -enable-kvm -cpu host -smp cores=2 \
    -kernel bzImage \
    -nic user,model=virtio-net-pci \
    -drive file=rootfs.img,if=virtio,cache=none,aio=native,format=raw,discard=on,readonly=on \
    -drive file=flag,if=virtio,format=raw,readonly=on \
    -virtfs local,path=init,mount_tag=init,security_model=none,readonly=on \
    -virtfs local,path=exp,mount_tag=exp,security_model=none,readonly=on \
    -append "'"$CMDLINE"'" \
    -nographic -no-reboot

    expect "# "
    send "id\n"

    expect "# "
    send "cat /flag\n"

    expect "# "
    send "exit\n"

    expect eof
' | tee $QEMU_TXT | sed $'s/\r//' &
QEMU_PID="$!"

while true; do
    # check if qemu.txt modified within $STDOUT_TIMEOUT seconds
    inotifywait -qq -t $STDOUT_TIMEOUT -e modify $QEMU_TXT &

    # wait for either QEMU or inotifywait to exit
    if ! wait -n $QEMU_PID $!; then break; fi

    # exit loop if QEMU exited already
    if ! ps -p $QEMU_PID > /dev/null; then break; fi
done

if ps -p $QEMU_PID > /dev/null; then
    echo "Repro error: no stdout response within the expected timeout of $STDOUT_TIMEOUT seconds"
    echo "Killing QEMU..."
    kill -9 $QEMU_PID
else
    echo "QEMU exited cleanly"
fi

echo "::$STOP_MARKER::"

cp $QEMU_TXT repro_log_$TRY_ID.txt
# echo "QEMU_OUTPUT_B64=$(cat $QEMU_TXT|base64 -w0)" >> "$GITHUB_OUTPUT"
echo "RUN_TIME=$(expr $(date +%s) - $START_TIME)" >> "$GITHUB_OUTPUT"

if grep -q $FLAG $QEMU_TXT; then
    echo "Got the flag! Congrats!"
    exit 0
else
    echo "Failed, did not get the flag."
    exit 1
fi
