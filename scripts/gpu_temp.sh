#!/usr/bin/env bash
# setting the locale, some users have issues with different locales, this forces the correct one
export LC_ALL=en_US.UTF-8

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $current_dir/utils.sh

get_platform()
{
  case $(uname -s) in
    Linux)
      # use this option for when your gpu isn't detected
      gpu_label=$(get_tmux_option "@dracula-force-gpu" false)
      if [[ "$gpu_label" != false ]]; then
        echo $gpu_label
      else
        # attempt to detect the gpu
        gpu=$(lspci -v 2> /dev/null | grep VGA | head -n 1 | awk '{print $5}')
        if [[ -n $gpu ]]; then
          # if a gpu is detected, return it
          echo $gpu
        elif type -a nvidia-smi >> /dev/null 2>&1; then
          # if no gpu was detected, and nvidia-smi is installed, we'll still try nvidia
          echo "NVIDIA"
        fi
      fi
      ;;

    Darwin)
      # GPU temperature is not exposed without root on macOS
      echo "apple"
      ;;

    CYGWIN*|MINGW32*|MSYS*|MINGW*)
      # nvidia-smi ships with the NVIDIA driver on Windows
      if type -a nvidia-smi >> /dev/null 2>&1; then
        echo "NVIDIA"
      fi
      ;;
  esac
}

# one "|<temp>C" entry per GPU, skipping GPUs that report "[N/A]"
get_nvidia_temp()
{
  type -a nvidia-smi >> /dev/null 2>&1 || return 1
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2> /dev/null |
    awk '$1 ~ /^[0-9]+$/ { printf("|%dC", $1); n++ } END { if (n) print "|"; else exit 1 }'
}

# AMD / Intel / nouveau: hwmon sensor of each DRM card (millidegrees)
get_hwmon_temp()
{
  local sensor temps=""
  for sensor in /sys/class/drm/card?/device/hwmon/hwmon?/temp1_input; do
    [[ -r "$sensor" ]] || continue
    temps+="|$(( $(cat "$sensor") / 1000 ))C"
  done
  [[ -n "$temps" ]] || return 1
  echo "$temps|"
}

get_gpu()
{
  gpu=$(get_platform)
  if [[ "$gpu" == NVIDIA ]]; then
    # fall back to hwmon when nvidia-smi is missing or the driver is not loaded (e.g. nouveau)
    usage=$(get_nvidia_temp || get_hwmon_temp)
  elif [[ "$gpu" == apple ]]; then
    usage=""
  elif [[ -n "$gpu" ]]; then # "Advanced", "Intel", etc
    usage=$(get_hwmon_temp)
  fi
  echo ${usage:-N/A}
}

main()
{
  # storing the refresh rate in the variable RATE, default is 5
  RATE=$(get_tmux_option "@dracula-refresh-rate" 5)
  gpu_label=$(get_tmux_option "@dracula-gpu-temp-label" "GPU")
  gpu_usage=$(get_gpu)
  echo "$gpu_label $gpu_usage"
  sleep $RATE
}

# run the main driver
main
