#!/usr/bin/env bash
# shx_binary example script

source "${RUNFILES}/examples/simple/demolib.sh"

demolib::log INFO "this function is sourced from inside the shx archive"
demolib::log INFO "My runfiles directory: $RUNFILES"
