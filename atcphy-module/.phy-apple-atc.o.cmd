savedcmd_phy-apple-atc.o := ld -EL  -maarch64linux -z norelro --compress-debug-sections=zlib -z noexecstack --no-warn-rwx-segments   -r -o phy-apple-atc.o @phy-apple-atc.mod 
