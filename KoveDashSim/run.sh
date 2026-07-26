#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"
echo "🚀 Launching Kove Dash Simulator..."
swift build --scratch-path ./build
./build/debug/KoveDashSim
