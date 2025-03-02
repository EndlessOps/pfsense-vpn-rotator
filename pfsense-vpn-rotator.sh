v#!/bin/sh

# ---------------------------------------------------------------------------------
# Script Name: pfSense Client VPN Rotator (pfsense-vpn-rotator.sh)
#
# Description: Automates the rotation of OpenVPN server addresses and ports for
#              OpenVPN client configurations on pfSense systems. This script uses
#              pfSsh.php for making configuration changes, avoiding direct editing
#              of config.xml and potential file corruption. It selects a random VPN
#              server from predefined lists, updates the OpenVPN client configuration,
#              and restarts the VPN service for seamless changes. Example server lists
#              are provided for ProtonVPN AU and US.
#
# Usage:       ./pfsense-vpn-rotator.sh <vpnid>
#              Replace <vpnid> with the appropriate VPN ID.
#
# Prerequisites: Fully configured and working OpenVPN client configurations on pfSense.
#                Access to pfSense shell and /usr/local/sbin/pfSsh.php.
#                Basic understanding of shell scripting and pfSense configuration.
#
# Installation: Copy the script to a directory like /usr/local/sbin on your pfSense
#               server and make it executable using 'chmod +x pfsense-vpn-rotator.sh'.
#
# Schedule:     Use the cron package in pfSense for scheduling the script execution.
#
# Github:       https://github.com/bradsec/pfsense-vpn-rotator
# License:      MIT License
# Disclaimer:   Script provided "as is", without warranty. Use at your own risk.
# ---------------------------------------------------------------------------------

current_date_time=$(date +"%H:%M:%S %d %b %Y")
vpnid="$1"

# Define your server lists, the number should match the vpnid
# The server_name is added to the OpenVPN client description for easy identification
server_name1="SurfShark US Endpoints 1"
#93.152.210.213 1443 End of SurfShark US Endpoints
#91.245.254.58 1443 Start of SurfShark CA Endpoints
#149.22.81.152 1443 End of SurfShark CA Endpoints
#185.108.105.79 1443 Start of SurfShark UK Endpoints
#217.146.83.105 1443 End of SurfShark UK Endpoints
server_list1="
146.70.186.133 1443
45.144.115.42 1443
185.141.119.62 1443
192.158.231.249 1443
149.40.50.196 1443
172.93.153.69 1443
154.47.25.103 1443
45.134.140.23 1443
45.43.19.211 1443
146.70.183.195 1443
74.80.182.72 1443
2.56.189.114 1443
149.40.56.17 1443
212.102.44.71 1443
93.152.220.170 1443
"
# Define your server lists, the number should match the vpnid
# The server_name is added to the OpenVPN client description for easy identification
server_name2="SurfShark US Endpoints 2"
#93.152.210.213 1443 End of SurfShark US Endpoints
#91.245.254.58 1443 Start of SurfShark CA Endpoints
#149.22.81.152 1443 End of SurfShark CA Endpoints
#185.108.105.79 1443 Start of SurfShark UK Endpoints
#217.146.83.105 1443 End of SurfShark UK Endpoints
server_list2="
45.86.211.64 1443
79.110.54.59 1443
66.235.168.215 1443
138.199.12.55 1443
185.193.157.162 1443
156.146.54.58 1443
93.152.210.213 1443
91.245.254.5 1443
37.19.211.22 1443
149.22.81.152 1443
185.108.105.79 1443
139.28.176.29 1443
188.240.57.123 1443
217.146.83.105 1443
146.70.175.69 1443
"

run_pfshell_cmd_getconfig() {
    tmpfile=/tmp/getovpnconfig.cmd
    tmpfile2=/tmp/getovpnconfig.output

    # Updated to use config_get_path for PHP 8.x compatibility
    echo 'print_r(config_get_path("openvpn/openvpn-client", array()));' >$tmpfile
    echo 'exec' >>$tmpfile
    echo 'exit' >>$tmpfile

    if ! output=$(/usr/local/sbin/pfSsh.php <$tmpfile); then
        echo "Error executing command."
        return 1
    fi

    echo "$output" >$tmpfile2
    echo "$output"
}

run_pfshell_cmd_get_server_addr() {
    local array_index="$1"

    # Check if /tmp/getovpnconfig.output exists and is readable
    if [ ! -r /tmp/getovpnconfig.output ]; then
        echo "Error: Unable to read /tmp/getovpnconfig.output."
        return 1
    fi

    # Use grep and awk to extract the server_addr for the given array_index
    # Assuming the format of the output file matches the provided sample
    server_addr=$(grep -A 20 "\[$array_index\] => Array" /tmp/getovpnconfig.output | grep "server_addr" | awk -F "=>" '{print $2}' | tr -d '[:space:]')

    if [ -z "$server_addr" ]; then
        echo "Error: server_addr not found for vpnid $vpnid."
        return 1
    fi

    echo "$server_addr"
}

run_pfshell_cmd_setconfig() {
    echo "Running pfSsh.php to set OpenVPN configuration..."
    tmpfile=/tmp/setovpnconfig.cmd
    array_index="$1"
    server_desc="$2"
    server_addr="$3"
    server_port="$4"

    # Updated to use config_set_path for PHP 8.x compatibility
    echo "config_set_path('openvpn/openvpn-client/${array_index}/description', 'vpnid${vpnid} ${server_desc}');" >$tmpfile
    echo "config_set_path('openvpn/openvpn-client/${array_index}/server_addr', '${server_addr}');" >>$tmpfile
    echo "config_set_path('openvpn/openvpn-client/${array_index}/server_port', '${server_port}');" >>$tmpfile
    echo 'write_config("Updating VPN client");' >>$tmpfile
    echo 'exec' >>$tmpfile
    echo 'exit' >>$tmpfile

    # Execute the file and capture the output
    output=$(/usr/local/sbin/pfSsh.php <"$tmpfile")
    echo "$output"
}

# Function to find the index of the array with the matching vpnid
find_vpnid_array_index() {
    local output="$1"

    echo "$output" | awk -v vpnid="$vpnid" '
    BEGIN { array_index = 0; found = 0 }
    /\[vpnid\] => / { 
        if ($3 == vpnid) { 
            found = 1; 
            exit;
        }
        array_index++;
    }
    END { if (found) print array_index; else print -1 }
    '
}

# Function to validate IPv4, IPv6, or a valid hostname
validate_server_address() {
    local address="$1"
    # Check for valid IPv4 or IPv6 address
    if echo "$address" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        return 0 # IPv4
    elif echo "$address" | grep -qE '^[0-9a-fA-F:]+$'; then
        return 0 # IPv6
    # Check for valid hostname (complying with RFC 1123)
    elif echo "$address" | grep -qE '^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.([a-zA-Z]{2,}|[a-zA-Z0-9-]{2,}\.[a-zA-Z]{2,})$'; then
        return 0 # Hostname
    else
        return 1 # Invalid address
    fi
}

# Function to validate port number
validate_port_number() {
    local port="$1"
    if echo "$port" | grep -qE '^[0-9]+$' && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0 # Valid port
    else
        return 1 # Invalid port
    fi
}

# Function to select a random line from a server list
select_random_server() {
    local server_list="$1"
    local current_server="$2"

    num_lines=$(echo "$server_list" | wc -l)
    local server_addr=""
    local server_port=""
    local attempts=0
    local max_attempts=10

    while [ $attempts -lt $max_attempts ]; do
        attempts=$((attempts + 1))

        # Generate a random number using od and head
        random_line=$(od -An -N2 -i /dev/urandom | awk -v num_lines="$num_lines" '{print ($1 % num_lines) + 1}')

        random_server_line=$(echo "$server_list" | sed -n "${random_line}p")
        server_addr=$(echo "$random_server_line" | awk '{print $1}')
        server_port=$(echo "$random_server_line" | awk '{print $2}')

        if validate_server_address "$server_addr" && validate_port_number "$server_port" && [ "$server_addr" != "$current_server" ]; then
            echo "$server_addr $server_port"
            return 0
        fi
    done

    echo "Error: Unable to select a different server address after $max_attempts attempts." >&2
    return 1
}

run_vpn_service_command() {
    local action="$1" # Action can be 'start', 'stop', or 'restart'

    # Validate the action using POSIX compliant syntax
    if [ "$action" != "start" ] && [ "$action" != "stop" ] && [ "$action" != "restart" ]; then
        echo "Invalid action: $action. Action must be 'start', 'stop', or 'restart'."
        return 1
    fi

    # Execute the command
    local command="/usr/local/sbin/pfSsh.php playback svc $action openvpn client $vpnid"
    echo "Executing: $command"

    if ! output=$($command); then
        echo "Error executing command."
        return 1
    fi

    echo "Command executed successfully."
    echo "$output"
}

main() {
    echo ""
    echo " ###########################################"
    echo " ## pfSense OpenVPN Client Rotator Script ##"
    echo " ###########################################"
    echo ""

    # Get the script name
    script_name=$(basename "$0")

    # Validate that vpnid is provided and is a number between 1 and 99
    if [ -z "$vpnid" ] || ! echo "$vpnid" | grep -qE '^[1-9][0-9]?$'; then
        echo "Error: vpnid not provided or is not a number between 1 and 99."
        echo "Usage: $script_name <vpnid>"
        echo "Example: $script_name 1"
        exit 1
    fi

    # Set the current IP address
    current_server="current_server_ADDRESS"

    # Determine which server list and name to use based on the argument
    vpn_server_list="server_list${vpnid}"
    vpn_server_name="server_name${vpnid}"

    # Use eval to construct the command to get the correct server list
    if ! eval "selected_server_list=\${$vpn_server_list}"; then
        echo "Error evaluating server list."
        exit 1
    fi

    if ! eval "selected_server_name=\${$vpn_server_name}"; then
        echo "Error evaluating server list."
        exit 1
    fi

    # Call run_pfshell_cmd and store the output
    echo "Fetching all OpenVPN client configurations..."
    pfssh_output=$(run_pfshell_cmd_getconfig)

    # Find the array index with the matching vpnid
    echo "Finding array index for vpnid $vpnid..."
    array_index=$(find_vpnid_array_index "$pfssh_output")

    # Check if a valid index was found
    if [ "$array_index" -ge 0 ]; then
        echo "Found OpenVPN configuration for vpnid $vpnid at array index: $array_index"
    else
        echo "No OpenVPN configuration for vpnid $vpnid found."
        exit 1
    fi

    # Get the server_addr for the given array index
    echo "Fetching current server_addr for vpnid $vpnid..."
    current_server_addr=$(run_pfshell_cmd_get_server_addr "$array_index")
    echo "The current server_addr for vpnid $vpnid is: $current_server_addr"

    # Check if the selected server list is not empty
    if [ -n "$selected_server_list" ]; then
        selected_server_addr_port=$(select_random_server "$selected_server_list" "$current_server")
    else
        echo "No server_list$vpnid defined in script."
        exit 1
    fi

    # Split the returned value into IP and port
    echo "Selecting random server address from server_list$vpnid..."
    selected_server_addr=$(echo "$selected_server_addr_port" | awk '{print $1}')
    selected_server_port=$(echo "$selected_server_addr_port" | awk '{print $2}')

    # Print the selected IP and port
    echo "Selected Server Address: $selected_server_addr"
    echo "Selected Server Port: $selected_server_port"

    # Call run_pfshell_cmd_setconfig and store the output
    echo "Setting new server address and port for vpnid $vpnid..."
    pfssh_output=$(run_pfshell_cmd_setconfig "$array_index" "$selected_server_name" "$selected_server_addr" "$selected_server_port")

    # Call run_vpn_service_command to restart the VPN service
    echo "Restarting OpenVPN service for vpnid $vpnid..."
    run_vpn_service_command "restart"

    # Clean up tmp files
    echo "Cleaning up temporary files..."
    rm /tmp/getovpnconfig.cmd
    rm /tmp/getovpnconfig.output

    echo "Script completed."
}

main "$@"
