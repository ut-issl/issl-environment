# shellcheck shell=bash

readlink="@readlink@"
env="@env@"
sleep="@sleep@"
grep="@grep@"
flock="@flock@"
percent="@percent@"
nix_package_nix="@nixPackageNix@"

self="$("$readlink" -f "$0")"
real="$nix_package_nix"
if [[ -z $real ]]; then
  IFS=: read -r -a path_entries <<< "${PATH:-}"
  for dir in "${path_entries[@]}"; do
    candidate="${dir}/nix"
    if [[ -z $dir ]] || [[ ! -f $candidate ]] || [[ ! -x $candidate ]]; then
      continue
    fi
    if [[ "$("$readlink" -f "$candidate")" == "$self" ]]; then
      continue
    fi
    magic=""
    read -r -n 2 magic < "$candidate" || true
    if [[ $magic == "#!" ]] && "$grep" -q ISSL_NIX_MEMORY_LIMITED "$candidate"; then
      continue
    fi
    real="$candidate"
    break
  done
fi
if [[ -z $real ]]; then
  echo "nix: no Nix found on PATH besides the ISSL memory limit wrapper" >&2
  exit 127
fi

run_unlimited() {
  exec "$real" "$@"
}

if [[ ${ISSL_NIX_MEMORY_LIMITED:-} == 1 ]] || [[ -n ${NIX_GET_COMPLETIONS:-} ]]; then
  run_unlimited "$@"
fi

subcommand=""
skip=0
for arg in "$@"; do
  if [[ $skip -gt 0 ]]; then
    skip=$((skip - 1))
    continue
  fi
  case "$arg" in
    --option) skip=2 ;;
    --store | --eval-store) skip=1 ;;
    build | bundle | config | copy | daemon | derivation | develop | doctor | edit | env | eval | flake | fmt | \
      formatter | hash | help | key | log | nar | path-info | print-dev-env | profile | realisation | \
      registry | repl | run | search | shell | store | upgrade-nix | why-depends)
      subcommand="$arg"
      break
      ;;
  esac
done
case "$subcommand" in
  develop | env | run | shell) run_unlimited "$@" ;;
esac

if [[ -z ${XDG_RUNTIME_DIR:-} ]] || [[ ! -S "${XDG_RUNTIME_DIR}/bus" ]]; then
  run_unlimited "$@"
fi
if ! command -v systemd-run > /dev/null || ! command -v systemctl > /dev/null; then
  run_unlimited "$@"
fi

slice=issl-nix.slice
lock_file="${XDG_RUNTIME_DIR}/issl-nix-memory-limit.lock"
lock_fd=""
release_lock() {
  if [[ -n $lock_fd ]]; then
    exec {lock_fd}>&-
    lock_fd=""
  fi
}
if ! : 2> /dev/null >> "$lock_file"; then
  run_unlimited "$@"
fi
exec {lock_fd}>> "$lock_file"
if ! "$flock" "$lock_fd"; then
  release_lock
  run_unlimited "$@"
fi

available_kb=""
while read -r key value _; do
  if [[ $key == "MemAvailable:" ]]; then
    available_kb="$value"
    break
  fi
done < /proc/meminfo
if [[ -z $available_kb ]]; then
  release_lock
  run_unlimited "$@"
fi

if ! slice_info="$(systemctl --user show --property=TasksCurrent --property=MemoryCurrent "$slice" 2> /dev/null)"; then
  release_lock
  run_unlimited "$@"
fi
tasks=""
used_bytes=""
while IFS='=' read -r key value; do
  case "$value" in
    "[not set]") value=0 ;;
    "" | *[!0-9]*) continue ;;
  esac
  case "$key" in
    TasksCurrent) tasks="$value" ;;
    MemoryCurrent) used_bytes="$value" ;;
  esac
done <<< "$slice_info"
if [[ -z $tasks ]] || [[ -z $used_bytes ]]; then
  release_lock
  run_unlimited "$@"
fi
limit_kb=$(((available_kb + used_bytes / 1024) * percent / 100))
used_kb=$(((used_bytes + 1023) / 1024))
margin_kb=$((used_kb / 10))
if [[ $margin_kb -lt 262144 ]]; then
  margin_kb=262144
fi
floor_kb=$((used_kb + margin_kb))
if [[ $tasks -gt 0 ]] && [[ $floor_kb -gt $limit_kb ]]; then
  limit_kb="$floor_kb"
fi
if ! systemctl --user set-property --runtime "$slice" \
  MemoryMax="${limit_kb}K" MemorySwapMax=0 2> /dev/null; then
  release_lock
  run_unlimited "$@"
fi
if [[ $tasks -gt 0 ]]; then
  release_lock
fi

start_limited() {
  if [[ -n $lock_fd ]]; then
    exec {lock_fd}>&-
  fi
  exec "$env" --default-signal=INT,QUIT ISSL_NIX_MEMORY_LIMITED=1 \
    systemd-run --user --scope --quiet --collect --slice="$slice" -- "$real" "$@"
}
start_limited "$@" <&0 &
child=$!
trap 'kill -TERM "$child" 2> /dev/null || true' TERM HUP
trap ':' INT QUIT
if [[ -n $lock_fd ]]; then
  polls=0
  while kill -0 "$child" 2> /dev/null; do
    if ! joined="$(systemctl --user show --property=TasksCurrent --value "$slice" 2> /dev/null)"; then
      break
    fi
    case "$joined" in
      "[not set]") ;;
      "" | *[!0-9]*) break ;;
      *) if [[ $joined -gt 0 ]]; then break; fi ;;
    esac
    if [[ $polls -lt 100 ]]; then
      "$sleep" 0.01 || true
    else
      "$sleep" 0.5 || true
    fi
    polls=$((polls + 1))
  done
  release_lock
fi
status=0
wait "$child" || status=$?
while kill -0 "$child" 2> /dev/null; do
  status=0
  wait "$child" || status=$?
done
if [[ $status -eq 137 ]]; then
  echo "nix: killed, likely for exceeding the memory limit of $((limit_kb / 1024)) MiB" \
    "that the running nix commands share" \
    "(${percent}% of the memory available to them when this one started)." >&2
  echo "nix: free up memory and retry, or adjust issl.nix.memoryLimit in your configuration." >&2
fi
exit "$status"
