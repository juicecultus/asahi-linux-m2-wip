#!/bin/bash
# DP Alt Mode tracing script for Machine B
# Traces the full USB-PD → TypeC PHY → DCP chain when a USB-C display is plugged in
# Run as root: sudo bash trace-dp-altmode.sh
#
# USAGE:
#   1. Start this script
#   2. Plug in a USB-C display/adapter
#   3. Wait 10 seconds
#   4. Unplug
#   5. Press Ctrl+C to stop
#   6. Find logs in /tmp/dp-altmode-trace/

set -e

OUTDIR="/tmp/dp-altmode-trace"
mkdir -p "$OUTDIR"

echo "=== DP Alt Mode Tracer ==="
echo "Output directory: $OUTDIR"

# 1. Snapshot kernel log position
dmesg -c > /dev/null 2>&1 || true
DMESG_START=$(date +%s)

# 2. Enable ftrace for the key functions in the DP Alt Mode chain
TRACEFS="/sys/kernel/debug/tracing"

if [ ! -d "$TRACEFS" ]; then
    mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
    mount -t tracefs none /sys/kernel/debug/tracing 2>/dev/null || true
fi

echo "Setting up ftrace..."
echo 0 > "$TRACEFS/tracing_on"
echo function_graph > "$TRACEFS/current_tracer"

# Clear previous filters
echo > "$TRACEFS/set_ftrace_filter"

# Key functions to trace in the DP Alt Mode chain:
# USB-PD controller (tipd/cd321x)
echo 'cd321x_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true
echo 'tps6598x_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true

# Type-C subsystem
echo 'typec_set_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true
echo 'typec_mux_set' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true
echo 'typec_switch_set' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true
echo 'typec_altmode_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true

# ATC PHY (Type-C PHY)
echo 'atcphy_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true

# DRM/DCP
echo 'dcp_dptx_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true
echo 'dptxport_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true
echo 'apple_connector_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true

# Display crossbar mux
echo 'mux_control_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true

# USB role switch
echo 'usb_role_switch_*' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true

# DRM OOB hotplug
echo 'drm_connector_oob_hotplug_event' >> "$TRACEFS/set_ftrace_filter" 2>/dev/null || true

echo "Trace filter set to:"
cat "$TRACEFS/set_ftrace_filter"
echo ""

# Also enable tracepoints for typec events
echo 1 > /sys/kernel/debug/tracing/events/enable 2>/dev/null || true

# 3. Start tracing
echo > "$TRACEFS/trace"
echo 1 > "$TRACEFS/tracing_on"

echo ""
echo ">>> TRACING ACTIVE <<<"
echo ">>> Now plug in a USB-C display or adapter <<<"
echo ">>> Press Ctrl+C when done <<<"
echo ""

# 4. Also dump typec sysfs state in background
dump_typec_state() {
    local outfile="$1"
    echo "=== $(date) ===" >> "$outfile"
    for port in /sys/class/typec/port*; do
        [ -d "$port" ] || continue
        echo "--- $port ---" >> "$outfile"
        for f in data_role power_role orientation preferred_role vconn_source; do
            [ -f "$port/$f" ] && echo "  $f: $(cat $port/$f)" >> "$outfile"
        done
        # Check for partners and alt modes
        for partner in "$port"/port*-partner; do
            [ -d "$partner" ] || continue
            echo "  partner: $partner" >> "$outfile"
            for am in "$partner"/*-altmode.*; do
                [ -d "$am" ] || continue
                echo "    altmode: $(basename $am)" >> "$outfile"
                for af in svid mode vdo active; do
                    [ -f "$am/$af" ] && echo "      $af: $(cat $am/$af)" >> "$outfile"
                done
            done
        done
    done
}

# Dump state every 2 seconds
(
    while true; do
        dump_typec_state "$OUTDIR/typec-state.log"
        sleep 2
    done
) &
BGPID=$!

# Wait for Ctrl+C
trap "echo 'Stopping trace...'; kill $BGPID 2>/dev/null; echo 0 > '$TRACEFS/tracing_on'" INT TERM

wait $BGPID 2>/dev/null || true

# 5. Save results
echo 0 > "$TRACEFS/tracing_on"
cp "$TRACEFS/trace" "$OUTDIR/ftrace.log"
dmesg > "$OUTDIR/dmesg.log"

# Dump DRM debugfs
if [ -d /sys/kernel/debug/dri ]; then
    cp -r /sys/kernel/debug/dri "$OUTDIR/dri-debug" 2>/dev/null || true
fi

echo ""
echo "=== Trace saved to $OUTDIR ==="
echo "Files:"
ls -la "$OUTDIR/"
