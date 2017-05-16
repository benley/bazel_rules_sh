#!bash

demolib::log() {
  level=$1 msg=$2
  shift 2
  printf -v formatted_msg "$msg" "$@"
  printf -v datestr '%(%m%d %H:%M:%S)T'
  printf "%s%s %s %s:%s] %s\n" "${level:0:1}" "$datestr" "$$" \
    "${BASH_SOURCE[1]##*/}" "${BASH_LINENO[0]}" \
    "${formatted_msg}" >&2
}
