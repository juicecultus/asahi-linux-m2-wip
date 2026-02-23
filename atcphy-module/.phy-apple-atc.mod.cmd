savedcmd_phy-apple-atc.mod := printf '%s\n'   atc.o | awk '!x[$$0]++ { print("./"$$0) }' > phy-apple-atc.mod
