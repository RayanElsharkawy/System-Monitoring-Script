#!/bin/bash

# Defaults value for Diskthreshold & report_file name
current_date=$(date '+%Y-%m-%d %H:%M:%S')
Diskthreshold=80
file_name=""
email="defaulemail@gmail.com"

# ----------------------------------- Help Fucntion -------------------------------------------
function help {
  echo "Usage: $0 [-t threshold] [-f filename]"
  echo
  echo "Options:"
  echo "  -t threshold    Set the disk usage threshold for the monitoring (default: $Diskthreshold)"
  echo "  -f filename     Set the filename for the generated report (default: monitoring_report_$(date '+%Y%m%d_%H%M%S').txt)"
  echo "  -h              Display this help message"
  echo
  echo "This script monitors disk usage, CPU usage, and memory usage, and generates a system report."
  echo "Caution: You should update the default email variable in the script if you will not specify one or use -e email."
  exit 1
}
# ----------------------------------- Email Function -------------------------------------------
function send_email {
  local subject="$1"
  local body="$2"
  local email="$3"
  echo -e "Subject: $subject\nContent-Type: text/html; charset=UTF-8\n\n<html><body>$body</body></html>" | msmtp "$email"
}
# ----------------------------------- Disk Usage Function -------------------------------------
function check_disk_usage {
  # Get the hostname and IP address of the machine
  machine_name=$(hostname)
  machine_ip=$(hostname -I | awk '{print $1}')

  # Get the disk usage and sort by usage percentage
  read disk_mount disk_usage <<< $(df -h --output=source,pcent | sort -k2 -n -r | head -n -1 | awk -v threshold=$Diskthreshold '$2+0 > threshold {print $1, $2}')
  emailsubj="Disk Space Warning: Immediate Action Required on $machine_name ($machine_ip)"

  # Extract disk details for the email body
  read fs_name size used avail use_perc mounted_on <<< $(df -h | sort -k5 -n -r | head -n 1 | awk '{print $1, $2, $3, $4, $5, $6}')

  # Construct the email body
  emailbody="<html>
  <body>
    <p>To Whom It May Concern,</p>
    <p>The following disk has exceeded the set usage threshold $Diskthreshold on the machine <b>$machine_name</b> (IP: <b>$machine_ip</b>):</p>
    <table border='1' style='border-collapse: collapse;'>
      <tr>
        <th>Filesystem</th>
        <th>Size</th>
        <th>Used</th>
        <th>Available</th>
        <th>Usage Percentage</th>
        <th>Mounted On</th>
      </tr>
      <tr>
        <td>$fs_name</td>
        <td>$size</td>
        <td>$used</td>
        <td>$avail</td>
        <td style='color: red;'>$use_perc</td>
        <td>$mounted_on</td>
      </tr>
    </table>
    <p><b style='color: red;'>WARNING: Immediate Action Required!</b></p>
    <p>The filesystem <b style='color: red;'>$fs_name</b> is currently <b style='color: red;'>$use_perc</b> full.</p>
    <p>To avoid potential system issues or interruptions, please take the necessary actions to free up space or expand capacity.</p>
    <p>Best regards,<br><b>System Monitoring Tool</b></p>
  </body>
  </html>"

  # Check if any disk exceeds the threshold
  if [ -z "$disk_mount" ]; then
    disk_results=$(df -h | sort -k5 -n | head -n 1 && df -h | sort -k5 -n -r)
    disk_results="$disk_results\nNo disk usage is greater than $Diskthreshold%. No warning."
  else
    disk_results=$(df -h | sort -k5 -n | head -n 1 && df -h | sort -k5 -n -r | head -n 1)
    disk_results="$disk_results\nWARNING !!!"
    send_email "$emailsubj" "$emailbody" "$email"
  fi
}
# ----------------------------------- CPU Usage Function --------------------------------------
function check_cpu_usage {
  # Get the current CPU usage percentage
  CPU_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
}
# ----------------------------------- Memory Usage Function -----------------------------------
function check_memory_usage {
  # Get memory usage stats
  read no mem_total no2 mem_used n3 mem_free <<< $(free -h | awk '/^Mem:/ {print "Total: " $2 ", Used: " $3 ", Free: " $4}')
}
# ----------------------------------- Get Top Processes Function ------------------------------
function get_top_processes {
  local n=$1     
  local order_by=$2  
  
  # Display top n processes ordered by the specified metric
  if [ "$order_by" == "cpu" ]; then
    ps -eo pid,user,comm,%cpu --sort=-%cpu | head -n $((n + 1)) 
  elif [ "$order_by" == "mem" ]; then
    ps -eo pid,user,comm,%mem --sort=-%mem | head -n $((n + 1)) 
  fi
}
# ----------------------------------- Handle Flags --------------------------------------------
while getopts "t:f:h:e:" opt; do
  case $opt in
    t)
      Diskthreshold=$OPTARG
      ;;
    f)
      file_name=$OPTARG
      ;;
    e)
      email=$OPTARG
      ;;
    h)
      help
      ;;
    *)
      echo "Usage: $0 [-t threshold] [-f filename] [-h]"
      exit 1
      ;;
  esac
done

if [ -z "$file_name" ]; then
  report_file="monitoring_report_$current_date.txt"
else
  # Append date to filename if user specifies one
  report_file="${file_name}_$current_date"
fi

# ----------------------------------- Extract System Information -----------------------------------
check_disk_usage
check_cpu_usage
check_memory_usage

# ----------------------------------- Create the Report -----------------------------------
{
  echo "System Monitoring Report"
  echo "Generated at: $current_date"
  echo "----------------------------------------"
  echo "Disk Usage:"
  echo -e "$disk_results"
  echo

  echo "Current CPU Usage: $CPU_usage%"
  echo "----------------------------------------"
  echo "Top 5 CPU-Consuming Processes:"
  get_top_processes 5 "cpu"
  echo

  echo "Memory Usage:"
  echo "Memory Total: $mem_total"
  echo "Memory Used: $mem_used"
  echo "Memory Free: $mem_free"
  echo "----------------------------------------"
  echo "Top 5 Memory-Consuming Processes:"
  get_top_processes 5 "mem"
  echo "----------------------------------------"
  echo "End of Report"
} > "$report_file"
