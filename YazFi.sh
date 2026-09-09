#!/bin/sh

###################################################
##                                               ##
##        __     __          ______  _           ##
##        \ \   / /         |  ____|(_)          ##
##         \ \_/ /__ _  ____| |__    _           ##
##          \   // _  ||_  /|  __|  | |          ##
##           | || (_| | / / | |     | |          ##
##           |_| \__,_|/___||_|     |_|          ##
##                                               ##
##       https://github.com/AMTM-OSR/YazFi       ##
## Forked from: https://github.com/jackyaz/YazFi ##
##                                               ##
###################################################
##      Credit to @RMerlin for the original      ##
##       Guest Network DHCP script and for       ##
##            AsusWRT-Merlin firmware            ##
###################################################
# Last Modified: 2026-Sep-08
#--------------------------------------------------

######       Shellcheck directives     ######
# shellcheck disable=SC1003
# shellcheck disable=SC1090
# shellcheck disable=SC2005
# shellcheck disable=SC2016
# shellcheck disable=SC2018
# shellcheck disable=SC2019
# shellcheck disable=SC2034
# shellcheck disable=SC2039
# shellcheck disable=SC2059
# shellcheck disable=SC2086
# shellcheck disable=SC2140
# shellcheck disable=SC2155
# shellcheck disable=SC3003
# shellcheck disable=SC3043
# shellcheck disable=SC3045
#############################################

### Start of script variables ###
readonly SCRIPT_NAME="YazFi"
readonly YAZFI_VERSION="v4.4.13"
readonly SCRIPT_VERSION="v4.4.13"
readonly SCRIPT_VERSTAG="26090823"
SCRIPT_BRANCH="develop"
SCRIPT_REPO="https://raw.githubusercontent.com/AMTM-OSR/${SCRIPT_NAME}/$SCRIPT_BRANCH"

readonly TEMP_DIR="/tmp/var/tmp"
readonly JFFS_ADDONS="/jffs/addons"
readonly JFFS_SCRIPTS="/jffs/scripts"
readonly SCRIPT_DIR="${JFFS_ADDONS}/${SCRIPT_NAME}.d"
readonly SCRIPT_CONF="${SCRIPT_DIR}/config"
readonly SCRIPT_FPATH="${JFFS_SCRIPTS}/$SCRIPT_NAME"
readonly USER_SCRIPT_DIR="${SCRIPT_DIR}/userscripts.d"
readonly SCRIPT_WEBPAGE_DIR="$(readlink -f /www/user)"
readonly SCRIPT_WEB_DIR="${SCRIPT_WEBPAGE_DIR}/$SCRIPT_NAME"
readonly SHARED_DIR="${JFFS_ADDONS}/shared-jy"
readonly SHARED_REPO="https://raw.githubusercontent.com/AMTM-OSR/shared-jy/master"
readonly SHARED_WEB_DIR="${SCRIPT_WEBPAGE_DIR}/shared-jy"
readonly TEMP_MENU_TREE="/tmp/menuTree.js"

# Optional integration with the native ASUS Network Map client list #
readonly NETWORKMAP_TARGET_JS="/www/client_function.js"
readonly NETWORKMAP_SOURCE_JS="${SCRIPT_DIR}/YazFi_networkmap.js"
readonly NETWORKMAP_JSON="$SCRIPT_WEB_DIR/networkmap_clients.json"
readonly NETWORKMAP_PIDFILE="/tmp/YazFi-networkmap.pid"
readonly NETWORKMAP_PATCH_JS="/tmp/YazFi-client_function.js"
readonly NETWORKMAP_BASE_JS="/tmp/YazFi-client_function.base.js"
readonly NETWORKMAP_MARKER="YAZFI_NETWORKMAP_INJECT_V1"
readonly NETWORKMAP_REFRESH_SECS=10
### End of script variables ###

### Start of output format variables ###
readonly CRIT="\e[41m"
readonly ERR="\e[31m"
readonly WARN="\e[33m"
readonly PASS="\e[32m"
readonly BOLD="\e[1m"
readonly CLEARFORMAT="\e[0m"
readonly CLRct="\e[0m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly MGNTct="\e[1;35m"
readonly CYANct="\e[1;36m"
readonly GRAYct="\e[0;37m"
readonly GRAYEDct="\e[0;30;47m"
readonly SETTING="${BOLD}${CYANct}"
### End of output format variables ###

### Start of router environment variables ###

# Workaround for Entware ELF binaries compiled with RUNPATH #
unset LD_LIBRARY_PATH

# Give higher priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

if [ -t 0 ] && ! tty | grep -qwi "NOT"
then readonly isInteractive=true
else readonly isInteractive=false
fi

##-------------------------------------##
## Added by Martinski W. [2026-Sep-05] ##
##-------------------------------------##
_PrintMsg_()
{ "$isInteractive" && printf "$1" ; }

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output()
{
	local prioStr  prioNum
	if [ $# -gt 2 ] && [ -n "$3" ]
	then prioStr="$3"
	else prioStr="NOTICE"
	fi
	if [ "$1" = "true" ] || [ "$1" = "LogOnly" ]
	then
		case "$prioStr" in
		    "$CRIT") prioNum=2 ;;
		     "$ERR") prioNum=3 ;;
		    "$WARN") prioNum=4 ;;
		    "$PASS") prioNum=6 ;; #INFO#
		          *) prioNum=5 ;; #NOTICE#
		esac
		logger -t "${SCRIPT_NAME}_[$$]" -p $prioNum "$2"
	fi
	if "$isInteractive" && [ "$1" != "LogOnly" ]
	then printf "${BOLD}${3}%s${CLRct}\n\n" "$2"
    fi
}

##-------------------------------------##
## Added by Martinski W. [2026-Sep-05] ##
##-------------------------------------##
readonly nvramInitUSleep=10
readonly nvramWaitUSleep=50
readonly nvramWaitFactor=20000
readonly nvramWaitSecMAX=2
readonly nvramWaitCntMAX="$((nvramWaitSecMAX * nvramWaitFactor))"
readonly nvramValueTempFPath="${TEMP_DIR}/nvramValue_${SCRIPT_NAME}_$$.TMP.TXT"
##-------------------------------------##
_NVRAM_Get_()
{
   local nvramProcID  nvramProcOK=false  retCode=1
   local waitCountNUM=0  logMsgStr  nvramKeyValue=""

   printf '' > "$nvramValueTempFPath"
   nvram get "$1" > "$nvramValueTempFPath" &
   nvramProcID="$!"
   usleep "$nvramInitUSleep"

   while true
   do
       if ! kill -EXIT "$nvramProcID" 2>/dev/null
       then nvramProcOK=true ; break
       fi
       usleep "$nvramWaitUSleep"
       waitCountNUM="$((waitCountNUM + 1))"
       if [ "$waitCountNUM" -ge "$nvramWaitCntMAX" ]
       then break
       fi
   done

   if kill -EXIT "$nvramProcID" 2>/dev/null
   then
       nvramProcOK=false
       kill -KILL "$nvramProcID" 2>/dev/null ; wait "$nvramProcID"
       logMsgStr="**ALERT**: Wait timeout [$nvramWaitSecMAX secs] for 'nvram get $1' command expired."
       Print_Output true "$logMsgStr" "$ERR"
   fi
   if "$nvramProcOK" && [ -s "$nvramValueTempFPath" ]
   then
       nvramKeyValue="$(cat "$nvramValueTempFPath")"
       retCode=0
   fi

   rm -f "$nvramValueTempFPath"
   echo "$nvramKeyValue"
   return "$retCode"
}

##----------------------------------------##
## Modified by Martinski W. [2024-Jun-23] ##
##----------------------------------------##
readonly LAN_IPaddr="$(_NVRAM_Get_ lan_ipaddr)"
readonly LAN_IFname="$(_NVRAM_Get_ lan_ifname)"
[ -z "$(_NVRAM_Get_ odmpid)" ] && ROUTER_MODEL="$(_NVRAM_Get_ productid)" || ROUTER_MODEL="$(_NVRAM_Get_ odmpid)"
ROUTER_MODEL="$(echo "$ROUTER_MODEL" | tr 'a-z' 'A-Z')"

##-------------------------------------##
## Added by Martinski W. [2025-Mar-16] ##
##-------------------------------------##
readonly scriptVersRegExp="v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})"
readonly webPageFileRegExp="user([1-9]|[1-2][0-9])[.]asp"
readonly webPageLineTabExp="\{url: \"$webPageFileRegExp\", tabName: "
readonly webPageLineRegExp="${webPageLineTabExp}\"$SCRIPT_NAME\"\},"
readonly branchxStr_TAG="[Branch: $SCRIPT_BRANCH]"
readonly versionDev_TAG="${SCRIPT_VERSION}_${SCRIPT_VERSTAG}"
readonly versionMod_TAG="$SCRIPT_VERSION on $ROUTER_MODEL"

readonly curlHTTPstatusStr="HTTP_Status_Code"
readonly curlTmpLogFile="${TEMP_DIR}/tmpCurl_${SCRIPT_NAME}_$$.TMP.LOG"
readonly curlErrLogFile="${TEMP_DIR}/tmpCurl_${SCRIPT_NAME}_$$.ERR.LOG"

# To support automatic script updates from AMTM #
doScriptUpdateFromAMTM=true

##-------------------------------------##
## Added by Martinski W. [2025-Mar-16] ##
##-------------------------------------##
readonly fwInstalledBaseVers="$(_NVRAM_Get_ firmver | sed 's/\.//g')"
readonly fwInstalledBuildVers="$(_NVRAM_Get_ buildno)"
readonly fwInstalledBranchVer="${fwInstalledBaseVers}.${fwInstalledBuildVers}"

# MAC addresses #
readonly MACaddr_RegExp="([a-fA-F0-9]{2}([:][a-fA-F0-9]{2}){5})"

##-------------------------------------##
## Added by Martinski W. [2022-Nov-18] ##
##-------------------------------------##
_GetWiFiVirtualInterfaceNames_()
{
   local wifiPrefix  wifiNames  wifiNameList=""  IFname  IFListStr=""

   for wifiPrefix in wl0 wl1 wl2 wl3
   do
       wifiNames="$(_NVRAM_Get_ "${wifiPrefix}_vifnames")"
       [ -z "$wifiNames" ] && continue
       wifiNameList="${wifiNameList:+$wifiNameList }$wifiNames"
   done

   for IFname in $wifiNameList
   do
       IFname="$(echo "$IFname" | grep -E "^wl[0-3][.][1-3]$")"
       [ -z "$IFname" ] && continue
       IFListStr="${IFListStr:+$IFListStr }$IFname"
   done

   echo "$IFListStr"
}

##----------------------------------------##
## Modified by Martinski W. [2024-Jan-06] ##
##----------------------------------------##
readonly IFACELIST_FULL="wl0.1 wl0.2 wl0.3 wl1.1 wl1.2 wl1.3 wl2.1 wl2.2 wl2.3 wl3.1 wl3.2 wl3.3"
readonly IFACELIST_ORIG="$(_GetWiFiVirtualInterfaceNames_)"
IFACELIST="$IFACELIST_ORIG"
### End of router environment variables ###

### Start of path variables ###
readonly DNSCONF="$SCRIPT_DIR/.dnsmasq"
readonly TMPCONF="$SCRIPT_DIR/.dnsmasq.tmp"
### End of path variables ###

### Start of firewall variables ###
readonly INPT="${SCRIPT_NAME}INPUT"
readonly FWRD="${SCRIPT_NAME}FORWARD"
readonly LGRJT="${SCRIPT_NAME}REJECT"
readonly DNSFLTR="${SCRIPT_NAME}DNSFILTER"
readonly DNSFLTR_DOT="${SCRIPT_NAME}DNSFILTER_DOT"
readonly CHAINS="$INPT $FWRD $LGRJT $DNSFLTR_DOT"
readonly NATCHAINS="$DNSFLTR"
### End of firewall variables ###

### Start of VPN clientlist variables ###
VPN_IP_LIST_ORIG_1=""
VPN_IP_LIST_ORIG_2=""
VPN_IP_LIST_ORIG_3=""
VPN_IP_LIST_ORIG_4=""
VPN_IP_LIST_ORIG_5=""
VPN_IP_LIST_NEW_1=""
VPN_IP_LIST_NEW_2=""
VPN_IP_LIST_NEW_3=""
VPN_IP_LIST_NEW_4=""
VPN_IP_LIST_NEW_5=""
### End of VPN clientlist variables ###

##----------------------------------------------##
## Added/modified by Martinski W. [2023-Jan-28] ##
##----------------------------------------------##
# DHCP Lease Time: Min & Max Values in seconds.
# 2 minutes=120 to 90 days=7776000 (inclusive).
# Single '0' or 'I' indicates "infinite" value.
#------------------------------------------------#
readonly MinDHCPLeaseTime=120
readonly MaxDHCPLeaseTime=7776000
readonly InfiniteLeaseTimeTag="I"
readonly InfiniteLeaseTimeVal="infinite"

##----------------------------------------##
## Modified by Martinski W. [2024-Jun-23] ##
##----------------------------------------##
readonly SUPPORTstr="$(_NVRAM_Get_ rc_support)"

Band_24G_Support=false
Band_5G_1_Support=false
Band_5G_2_support=false
Band_6G_1_Support=false
Band_6G_2_Support=false

if echo "$SUPPORTstr" | grep -qw '2.4G'
then Band_24G_Support=true ; fi

if echo "$SUPPORTstr" | grep -qw '5G'
then Band_5G_1_Support=true ; fi

if echo "$SUPPORTstr" | grep -qw 'wifi6e'
then Band_6G_1_Support=true ; fi

##-------------------------------------##
## Added by Martinski W. [2024-Jul-21] ##
##-------------------------------------##
_GetWiFiBandsSupported_()
{
   local wifiIFNameList  wifiIFName  wifiBandInfo  wifiBandName
   local wifi5GHzCount=0  wifi6GHzCount=0  wifiRadioStatus

   wifiIFNameList="$(_NVRAM_Get_ wl_ifnames)"
   if [ -z "$wifiIFNameList" ]
   then
       printf "\n**ERROR**: WiFi Interface List is *NOT* found.\n"
       return 1
   fi

   for wifiIFName in $wifiIFNameList
   do
       wifiBandInfo="$(wl -i "$wifiIFName" status 2>/dev/null | grep 'Chanspec:')"
       if [ -z "$wifiBandInfo" ]
       then
           wifiRadioStatus="$(wl -i "$wifiIFName" bss 2>/dev/null)"
           if [ "$wifiRadioStatus" = "down" ]
           then
               printf "\n${WARN}*WARNING*: Wireless Radio for WiFi Interface [$wifiIFName] is down.${CLEARFORMAT}\n"
           elif [ "$wifiRadioStatus" = "up" ]
           then
               printf "\n${ERR}**ERROR**: Could not find 'Chanspec' for WiFi Interface [$wifiIFName].${CLEARFORMAT}\n"
           else
               printf "\n${WARN}*WARNING*: Wireless Radio for WiFi Interface [$wifiIFName] is disabled.${CLEARFORMAT}\n"
           fi
           continue
       fi
       wifiBandName="$(echo "$wifiBandInfo" | awk -F ' ' '{print $2}')"

       case "$wifiBandName" in
           2.4GHz) Band_24G_Support=true
                   ;;
             5GHz) wifi5GHzCount="$((wifi5GHzCount + 1))"
                   [ "$wifi5GHzCount" -eq 1 ] && Band_5G_1_Support=true
                   [ "$wifi5GHzCount" -eq 2 ] && Band_5G_2_support=true
                   ;;
             6GHz) wifi6GHzCount="$((wifi6GHzCount + 1))"
                   [ "$wifi6GHzCount" -eq 1 ] && Band_6G_1_Support=true
                   [ "$wifi6GHzCount" -eq 2 ] && Band_6G_2_Support=true
                   ;;
                *) printf "\nWiFi Interface=[$wifiIFName], WiFi Band=[$wifiBandName]\n"
                   ;;
       esac
   done
}

_GetWiFiBandsSupported_

Generate_Random_String()
{
	PASSLENGTH=16
	if Validate_Number '' "$1" silent
	then
		if [ "$1" -le 32 ] && [ "$1" -ge 8 ]
		then
			PASSLENGTH="$1"
		else
			printf "${BOLD}Number is not between 8 and 32, using default of 16 characters${CLRct}\n"
		fi
	else
		printf "${BOLD}Invalid number provided, using default of 16 characters${CLRct}\n"
	fi
	< /dev/urandom tr -cd 'A-Za-z0-9' | head -c "$PASSLENGTH"
}

Escape_Sed()
{ sed -e 's/</\\</g;s/>/\\>/g;s/ /\\ /g' ; }

Get_Iface_Var()
{ echo "$1" | sed -e 's/\.//g' ; }

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_DOStoUNIX_()
{
    if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -s "$1" ]
    then return 1 ; fi
    if grep -q "$(printf '\r\n')" "$1" 2>/dev/null
    then dos2unix "$1" ; fi
}

##----------------------------------------##
## Modified by Martinski W. [2024-Jul-21] ##
##----------------------------------------##
GetIFaceUILabel()
{
    if [ $# -eq 0 ] || [ -z "$1" ] ; then echo "" ; return 1 ; fi

    theUILabel="*UNKNOWN*"
    case "$1" in
        wl0)
            if { [ "$ROUTER_MODEL" = "GT-BE98" ] || \
                 [ "$ROUTER_MODEL" = "GT-BE98_PRO" ] || \
                 [ "$ROUTER_MODEL" = "GT-AXE16000" ] ; } && \
               "$Band_5G_1_Support"
            then theUILabel="5GHz"
            elif "$Band_24G_Support"
            then theUILabel="2.4GHz"
            fi
            ;;
        wl1)
            if [ "$ROUTER_MODEL" = "GT-BE98_PRO" ] && \
               "$Band_6G_1_Support"
            then 
                theUILabel="6GHz"
            elif { [ "$ROUTER_MODEL" = "GT-BE98" ] || \
                   [ "$ROUTER_MODEL" = "GT-AXE16000" ] ; } && \
                 "$Band_5G_2_support"
            then theUILabel="5GHz2"
            elif "$Band_5G_1_Support"
            then theUILabel="5GHz"
            fi
            ;;
        wl2)
            if [ "$ROUTER_MODEL" = "GT-BE98_PRO" ] || \
               "$Band_6G_2_Support"
            then theUILabel="6GHz-2"
            elif [ "$ROUTER_MODEL" = "GT-AXE16000" ] || \
                 "$Band_6G_1_Support"
            then theUILabel="6GHz"
            elif "$Band_5G_2_support"
            then theUILabel="5GHz2"
            fi
            ;;
        wl3)
            if { [ "$ROUTER_MODEL" = "GT-BE98" ] || \
                 [ "$ROUTER_MODEL" = "GT-BE98_PRO" ] || \
                 [ "$ROUTER_MODEL" = "GT-AXE16000" ] ; } && \
               "$Band_24G_Support"
            then theUILabel="2.4GHz"
            fi
            ;;
    esac
    echo "$theUILabel"
}

##----------------------------------------##
## Modified by Martinski W. [2022-Dec-23] ##
##----------------------------------------##
Menu_Get_Guest_Name()
{
	if [ $# -eq 0 ] || [ -z "$1" ] ; then echo ; fi
	theIFprefix="$(echo "$1" | cut -d '.' -f1)"
	theIFnumber="$(echo "$1" | cut -d '.' -f2)"
	theIFlabel="$(GetIFaceUILabel "$theIFprefix")"

	echo "YazFi $theIFlabel GN#$theIFnumber"
}

##----------------------------------------##
## Modified by Martinski W. [2022-Dec-23] ##
##----------------------------------------##
Get_Guest_Name()
{
	if [ $# -eq 0 ] || [ -z "$1" ] ; then echo ; fi
	theIFprefix="$(echo "$1" | cut -d '.' -f1)"
	theIFnumber="$(echo "$1" | cut -d '.' -f2)"
	theIFlabel="$(GetIFaceUILabel "$theIFprefix")"

	echo "YazFi $theIFlabel $theIFnumber"
}

##----------------------------------------##
## Modified by Martinski W. [2022-Dec-23] ##
##----------------------------------------##
Get_Guest_Name_Old()
{
	if [ $# -eq 0 ] || [ -z "$1" ] ; then echo ; fi
	theIFprefix="$(echo "$1" | cut -d '.' -f1)"
	theIFnumber="$(echo "$1" | cut -d '.' -f2)"
	theIFlabel="$(GetIFaceUILabel "$theIFprefix")"

	if [ "$theIFlabel" = "5GHz" ]
	then theIFlabel="5GHz1" ; fi

	echo "$theIFlabel Guest $theIFnumber"
}

Set_WiFi_Passphrase()
{
	nvram set "${1}_wpa_psk"="$2"
	nvram set "${1}_auth_mode_x"="psk2"
	nvram set "${1}_akm"="psk2"
	nvram commit
}

Iface_Manage()
{
	case $1 in
		create)
			ifconfig "$2" "$(eval echo '$'"$(Get_Iface_Var "$2")"_IPADDR | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")" netmask 255.255.255.0
		;;
		delete)
			ifconfig "$2" 0.0.0.0
		;;
		deleteall)
			for IFACE in $IFACELIST
			do Iface_Manage delete "$IFACE"
			done
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2024-Jan-03] ##
##----------------------------------------##
Iface_BounceClients()
{
	local callSleep=false
	if [ -n "$IFACELIST" ]
	then
		Print_Output true "Forcing $SCRIPT_NAME Guest WiFi clients to reauthenticate" "$PASS"
		Print_Output false "Please wait..." "$PASS"
	fi

	for IFACE in $IFACELIST
	do
		callSleep=true
		wl -i "$IFACE" radio off >/dev/null 2>&1
	done
	"$callSleep" && sleep 10

	for IFACE in $IFACELIST
	do
		callSleep=true
		wl -i "$IFACE" radio on >/dev/null 2>&1
	done
	"$callSleep" && sleep 2

	ARP_CACHE="/proc/net/arp"
	for IFACE in $IFACELIST
	do
		if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ENABLED")" = "true" ]
		then
			IFACE_MACS="$(wl -i "$IFACE" assoclist)"
			if [ "$IFACE_MACS" != "" ]
			then
				IFS=$'\n'
				for GUEST_MAC in $IFACE_MACS
				do
					GUEST_MACADDR="${GUEST_MAC#* }"
					GUEST_ARPCOUNT="$(grep -ic "$GUEST_MACADDR" "$ARP_CACHE")"
					[ "$GUEST_ARPCOUNT" -eq 0 ] && continue

					GUEST_ARPINFO="$(grep -i "$GUEST_MACADDR" "$ARP_CACHE")"
					for ARP_ENTRY in $GUEST_ARPINFO
					do
						GUEST_IPADDR="$(echo "$ARP_ENTRY" | awk -F ' ' '{print $1}')"
						arp -d "$GUEST_IPADDR"
					done
				done
				unset IFS
			fi
		fi
	done

	ip -s -s neigh flush all >/dev/null 2>&1
	killall -q networkmap
	sleep 5
	if [ -z "$(pidof networkmap)" ]; then
		networkmap >/dev/null 2>&1 &
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Auto_DNSMASQ()
{
	case $1 in
		create)
			if [ -s /jffs/scripts/dnsmasq.postconf ]
			then
				STARTUPLINECOUNT="$(grep -c "# $SCRIPT_NAME" /jffs/scripts/dnsmasq.postconf)"
				STARTUPLINECOUNTEX="$(grep -cx "cat $DNSCONF >> /etc/dnsmasq.conf # $SCRIPT_NAME" /jffs/scripts/dnsmasq.postconf)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/dnsmasq.postconf
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					echo "cat $DNSCONF >> /etc/dnsmasq.conf # $SCRIPT_NAME" >> /jffs/scripts/dnsmasq.postconf
				fi
				if [ "$(grep -c "NextDNS" /jffs/scripts/dnsmasq.postconf)" -gt 0 ]
				then
					sed -i '/exit 0/d' /jffs/scripts/dnsmasq.postconf
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/dnsmasq.postconf
				echo >> /jffs/scripts/dnsmasq.postconf
				echo "cat $DNSCONF >> /etc/dnsmasq.conf # $SCRIPT_NAME" >> /jffs/scripts/dnsmasq.postconf
			fi
			chmod 0755 /jffs/scripts/dnsmasq.postconf
		;;
		delete)
			if [ -s /jffs/scripts/dnsmasq.postconf ]
			then
				STARTUPLINECOUNT="$(grep -c "# $SCRIPT_NAME" /jffs/scripts/dnsmasq.postconf)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/dnsmasq.postconf
				fi
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Auto_ServiceEvent()
{
	case $1 in
		create)
			if [ -s /jffs/scripts/service-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME Guest Networks" /jffs/scripts/service-event)"
				STARTUPLINECOUNTEX="$(grep -cx 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'" || { \[ "$1" = "restart" \] && \[ "$2" = "wireless" \]; }; then { /jffs/scripts/'"$SCRIPT_NAME"' service_event "$@" & }; fi # '"$SCRIPT_NAME Guest Networks" /jffs/scripts/service-event)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/service-event
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'" || { [ "$1" = "restart" ] && [ "$2" = "wireless" ]; }; then { /jffs/scripts/'"$SCRIPT_NAME"' service_event "$@" & }; fi # '"$SCRIPT_NAME Guest Networks" >> /jffs/scripts/service-event
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/service-event
				echo >> /jffs/scripts/service-event
				echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'" || { [ "$1" = "restart" ] && [ "$2" = "wireless" ]; }; then { /jffs/scripts/'"$SCRIPT_NAME"' service_event "$@" & }; fi # '"$SCRIPT_NAME Guest Networks" >> /jffs/scripts/service-event
			fi
			chmod 0755 /jffs/scripts/service-event
		;;
		delete)
			if [ -s /jffs/scripts/service-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME"' Guest Networks' /jffs/scripts/service-event)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/service-event
				fi
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Auto_Startup()
{
	case $1 in
		create)
			if [ -s /jffs/scripts/firewall-start ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME"' Guest Networks' /jffs/scripts/firewall-start)"
				STARTUPLINECOUNTEX="$(grep -cx "$SCRIPT_FPATH runnow & # $SCRIPT_NAME Guest Networks" /jffs/scripts/firewall-start)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/firewall-start
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					echo "$SCRIPT_FPATH runnow & # $SCRIPT_NAME Guest Networks" >> /jffs/scripts/firewall-start
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/firewall-start
				echo >> /jffs/scripts/firewall-start
				echo "$SCRIPT_FPATH runnow & # $SCRIPT_NAME Guest Networks" >> /jffs/scripts/firewall-start
			fi
			chmod 0755 /jffs/scripts/firewall-start
		;;
		delete)
			if [ -s /jffs/scripts/firewall-start ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME"' Guest Networks' /jffs/scripts/firewall-start)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/firewall-start
				fi
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Auto_ServiceEventEnd()
{
	case $1 in
		create)
			if [ -s /jffs/scripts/firewall-start ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME"' Guest Networks' /jffs/scripts/firewall-start)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/firewall-start
				fi
			fi
			if [ -s /jffs/scripts/service-event-end ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME Guest Networks" /jffs/scripts/service-event-end)"
				STARTUPLINECOUNTEX="$(grep -cx 'if { \[ "$1" = "start" \] || \[ "$1" = "restart" \]; } && \[ "$2" = "firewall" \]; then { /jffs/scripts/'"$SCRIPT_NAME"' runnow & }; fi # '"$SCRIPT_NAME Guest Networks" /jffs/scripts/service-event-end)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/service-event-end
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					echo 'if { [ "$1" = "start" ] || [ "$1" = "restart" ]; } && [ "$2" = "firewall" ]; then { /jffs/scripts/'"$SCRIPT_NAME"' runnow & }; fi # '"$SCRIPT_NAME Guest Networks" >> /jffs/scripts/service-event-end
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/service-event-end
				echo >> /jffs/scripts/service-event-end
				echo 'if { [ "$1" = "start" ] || [ "$1" = "restart" ]; } && [ "$2" = "firewall" ]; then { /jffs/scripts/'"$SCRIPT_NAME"' runnow & }; fi # '"$SCRIPT_NAME Guest Networks" >> /jffs/scripts/service-event-end
			fi
			chmod 0755 /jffs/scripts/service-event-end
		;;
		delete)
			if [ -s /jffs/scripts/firewall-start ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME"' Guest Networks' /jffs/scripts/firewall-start)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/firewall-start
				fi
			fi
			if [ -s /jffs/scripts/service-event-end ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME"' Guest Networks' /jffs/scripts/service-event-end)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"' Guest Networks/d' /jffs/scripts/service-event-end
				fi
			fi
		;;
	esac
}

##---------------------------------------##
## Added by ExtremeFiretop [2026-Jul-02] ##
##---------------------------------------##
Auto_NetworkMapServiceEventEnd()
{
	local HOOKFILE="/jffs/scripts/service-event-end"
	case $1 in
		create)
			if [ ! -s "$HOOKFILE" ]
			then
				printf '#!/bin/sh\n\n' > "$HOOKFILE"
			fi
			if ! grep -qF "# $SCRIPT_NAME Network Map" "$HOOKFILE"
			then
				echo 'if { [ "$1" = "start" ] || [ "$1" = "restart" ]; } && [ "$2" = "httpd" ]; then /jffs/scripts/'"$SCRIPT_NAME"' networkmap remount >/dev/null 2>&1 & fi # '"$SCRIPT_NAME"' Network Map' >> "$HOOKFILE"
			fi
			chmod 0755 "$HOOKFILE"
		;;
		delete)
			[ -s "$HOOKFILE" ] && sed -i '/# '"$SCRIPT_NAME"' Network Map/d' "$HOOKFILE"
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Auto_ServiceStart()
{
	case $1 in
		create)
			if [ -s /jffs/scripts/services-start ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/services-start)"
				STARTUPLINECOUNTEX="$(grep -cx "$SCRIPT_FPATH startup & # $SCRIPT_NAME" /jffs/scripts/services-start)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/services-start
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					echo "$SCRIPT_FPATH startup & # $SCRIPT_NAME" >> /jffs/scripts/services-start
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/services-start
				echo >> /jffs/scripts/services-start
				echo "$SCRIPT_FPATH startup & # $SCRIPT_NAME" >> /jffs/scripts/services-start
			fi
			chmod 0755 /jffs/scripts/services-start
		;;
		delete)
			if [ -s /jffs/scripts/services-start ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/services-start)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/services-start
				fi
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Auto_OpenVPNEvent()
{
	case $1 in
		create)
			if [ -s /jffs/scripts/openvpn-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/openvpn-event)"
				STARTUPLINECOUNTEX="$(grep -cx "$SCRIPT_FPATH openvpn "'$1 $script_type & # '"$SCRIPT_NAME" /jffs/scripts/openvpn-event)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/openvpn-event
				fi
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					sed -i '2 i /jffs/scripts/'"$SCRIPT_NAME"' openvpn $1 $script_type & # '"$SCRIPT_NAME" /jffs/scripts/openvpn-event
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/openvpn-event
				echo >> /jffs/scripts/openvpn-event
				echo "$SCRIPT_FPATH openvpn "'$1 $script_type & # '"$SCRIPT_NAME" >> /jffs/scripts/openvpn-event
			fi
			chmod 0755 /jffs/scripts/openvpn-event
		;;
		delete)
			if [ -s /jffs/scripts/openvpn-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/openvpn-event)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/openvpn-event
				fi
			fi
		;;
	esac
}

Auto_Cron()
{
	case $1 in
		create)
			STARTUPLINECOUNT="$(cru l | grep -c "$SCRIPT_NAME")"
			if [ "$STARTUPLINECOUNT" -eq 0 ]
			then
				cru a "$SCRIPT_NAME" "*/10 * * * * $SCRIPT_FPATH check"
			fi
		;;
		delete)
			STARTUPLINECOUNT="$(cru l | grep -c "$SCRIPT_NAME")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]
			then
				cru d "$SCRIPT_NAME"
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Avahi_Conf()
{
	case $1 in
		create)
			if [ -s /jffs/scripts/avahi-daemon.postconf ]
			then
				chmod 0755 /jffs/scripts/avahi-daemon.postconf
				STARTUPLINECOUNT="$(grep -c "$SCRIPT_NAME" /jffs/scripts/avahi-daemon.postconf)"
				if [ "$STARTUPLINECOUNT" -eq 0 ]
				then
					{
					   echo 'echo "" >> "$1" # '"$SCRIPT_NAME"
					   echo 'echo "[reflector]" >> "$1" # '"$SCRIPT_NAME"
					   echo 'echo "enable-reflector=yes" >> "$1" # '"$SCRIPT_NAME"
					   echo "sed -i '/^\[Server\]/a cache-entries-max=0' "'"$1" # '"$SCRIPT_NAME"
					} >> /jffs/scripts/avahi-daemon.postconf
					service restart_mdns >/dev/null 2>&1
				fi
			else
				{
				   echo '#!/bin/sh'
				   echo 'echo "" >> "$1" # '"$SCRIPT_NAME"
				   echo 'echo "[reflector]" >> "$1" # '"$SCRIPT_NAME"
				   echo 'echo "enable-reflector=yes" >> "$1" # '"$SCRIPT_NAME"
				   echo "sed -i '/^\[Server\]/a cache-entries-max=0' "'"$1" # '"$SCRIPT_NAME"
				} > /jffs/scripts/avahi-daemon.postconf
				chmod 0755 /jffs/scripts/avahi-daemon.postconf
				service restart_mdns >/dev/null 2>&1
			fi
		;;
		delete)
			if [ -s /jffs/scripts/avahi-daemon.postconf ]
			then
				STARTUPLINECOUNT="$(grep -c "$SCRIPT_NAME" /jffs/scripts/avahi-daemon.postconf)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/avahi-daemon.postconf
					service restart_mdns >/dev/null 2>&1
				fi
			fi
		;;
	esac
}

_FWVersionStrToNum_()
{ echo "$1" | awk -F '.' '{ printf ("%d%03d%02d%02d\n", $1,$2,$3,$4); }' ; }

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-18] ##
##----------------------------------------##
_Firmware_Support_Check_()
{
	local FW_NOT_Supported=false

	if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.384.5)" ] && \
	   [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -ne "$(_FWVersionStrToNum_ 3004.374.43)" ]
	then
		Print_Output true "Older RMerlin firmware detected - service-event requires 384.5 or later" "$WARN"
		Print_Output true "Please update to benefit from $SCRIPT_NAME detecting wireless restarts" "$WARN"
	elif [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -eq "$(_FWVersionStrToNum_ 3004.374.43)" ]
	then
		Print_Output true "John's fork detected - service-event requires 374.43_32D6j9527 or later" "$WARN"
		Print_Output true "Please update to benefit from $SCRIPT_NAME detecting wireless restarts" "$WARN"
	elif [ "$fwInstalledBaseVers" -ge 3006 ]
	then
		FW_NOT_Supported=true ; echo
		Print_Output true "F/W ${fwInstalledBranchVer}.* version detected. YazFi is NOT supported on this firmware." "$ERR"
	fi

	if "$FW_NOT_Supported"
	then return 1
	else return 0
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
_Firmware_Version_WebUI_()
{
	if _NVRAM_Get_ rc_support | grep -qF 'am_addons'
	then return 0
	fi
	Print_Output true "Unsupported firmware version detected" "$ERR"
	Print_Output true "WebUI is supported only on firmware versions with add-on support" "$ERR"
	return 1
}

### Code for these functions inspired by https://github.com/Adamm00 - credit to @Adamm ###
Check_Lock()
{
	if [ -f "/tmp/$SCRIPT_NAME.lock" ]
	then
		ageoflock="$(($(date +%s) - $(date +%s -r /tmp/$SCRIPT_NAME.lock)))"
		if [ "$ageoflock" -gt 600 ]
		then
			Print_Output true "Stale lock file found (>600 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' /tmp/$SCRIPT_NAME.lock)" >/dev/null 2>&1
			Clear_Lock
			echo "$$" > "/tmp/$SCRIPT_NAME.lock"
			return 0
		else
			Print_Output true "Lock file found (age: $ageoflock seconds) - stopping to prevent duplicate runs" "$ERR"
			if [ $# -eq 0 ] || [ -z "$1" ]; then
				exit 1
			else
				return 1
			fi
		fi
	else
		echo "$$" > "/tmp/$SCRIPT_NAME.lock"
		return 0
	fi
}

Clear_Lock()
{
	rm -f "/tmp/$SCRIPT_NAME.lock" 2>/dev/null
	return 0
}

##----------------------------------------##
## Modified by Martinski W. [2025-Mar-16] ##
##----------------------------------------##
Set_Version_Custom_Settings()
{
	SETTINGSFILE="${JFFS_ADDONS}/custom_settings.txt"
	case "$1" in
		local)
			if [ -f "$SETTINGSFILE" ]
			then
				if [ "$(grep -c "^yazfi_version_local" "$SETTINGSFILE")" -gt 0 ]
				then
					if [ "$SCRIPT_VERSION" != "$(grep "^yazfi_version_local" "$SETTINGSFILE" | cut -f2 -d' ')" ]
					then
						sed -i "s/^yazfi_version_local.*/yazfi_version_local $2/" "$SETTINGSFILE"
					fi
				else
					echo "yazfi_version_local $2" >> "$SETTINGSFILE"
				fi
			else
				echo "yazfi_version_local $2" >> "$SETTINGSFILE"
			fi
		;;
		server)
			if [ -f "$SETTINGSFILE" ]
			then
				if [ "$(grep -c "^yazfi_version_server" "$SETTINGSFILE")" -gt 0 ]
				then
					if [ "$2" != "$(grep "^yazfi_version_server" "$SETTINGSFILE" | cut -f2 -d' ')" ]
					then
						sed -i "s/^yazfi_version_server.*/yazfi_version_server $2/" "$SETTINGSFILE"
					fi
				else
					echo "yazfi_version_server $2" >> "$SETTINGSFILE"
				fi
			else
				echo "yazfi_version_server $2" >> "$SETTINGSFILE"
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Mar-16] ##
##----------------------------------------##
Update_Check()
{
	echo 'var updatestatus = "InProgress";' > "${SCRIPT_WEB_DIR}/detect_update.js"
	tempFPathSHx="${TEMP_DIR}/${SCRIPT_NAME}.TMP.SH" ; rm -f "$tempFPathSHx"
	if ! Download_File "$SCRIPT_REPO" "${SCRIPT_NAME}.sh" "$tempFPathSHx"
	then
		Print_Output true "$SCRIPT_NAME script was NOT updated. Download failed." "$ERR"
		echo 'var updatestatus = "None";' > "${SCRIPT_WEB_DIR}/detect_update.js"
		echo "false,$SCRIPT_VERSION,$SCRIPT_VERSION"
		return 1
	fi

	getUpdate="false"
	localVers="$(grep '^readonly SCRIPT_VERSION=' "$SCRIPT_FPATH" | grep -m1 -oE "$scriptVersRegExp")"
	serverVer="$(grep '^readonly SCRIPT_VERSION=' "$tempFPathSHx" | grep -m1 -oE "$scriptVersRegExp")"
	if [ "$localVers" != "$serverVer" ]
	then
		getUpdate="version"
		Set_Version_Custom_Settings server "$serverVer"
		echo 'var updatestatus = "'"$serverVer"'";'  > "${SCRIPT_WEB_DIR}/detect_update.js"
	else
		localxMD5="$(md5sum "$SCRIPT_FPATH" | awk '{print $1}')"
		remoteMD5="$(md5sum "$tempFPathSHx" | awk '{print $1}')"
		if [ "$localxMD5" != "$remoteMD5" ]
		then
			getUpdate="md5"
			Set_Version_Custom_Settings server "${serverVer}-hotfix"
			echo 'var updatestatus = "'"${serverVer}-hotfix"'";'  > "${SCRIPT_WEB_DIR}/detect_update.js"
		fi
	fi
	if [ "$getUpdate" = "false" ]
	then
		echo 'var updatestatus = "None";'  > "${SCRIPT_WEB_DIR}/detect_update.js"
	fi
	rm -f "$tempFPathSHx"
	echo "$getUpdate,$localVers,$serverVer"
	return 0
}

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
Update_Version()
{
	if [ $# -eq 0 ] || [ -z "$1" ]
	then
		updateCheckResult="$(Update_Check)"
		getUpdate="$(echo "$updateCheckResult" | cut -d',' -f1)"
		localVers="$(echo "$updateCheckResult" | cut -d',' -f2)"
		serverVer="$(echo "$updateCheckResult" | cut -d',' -f3)"

		if [ "$getUpdate" = "version" ]
		then
			Print_Output true "New version of $SCRIPT_NAME available - $serverVer" "$PASS"
		elif [ "$getUpdate" = "md5" ]
		then
			Print_Output true "MD5 hash of $SCRIPT_NAME does NOT match - hotfix available - $serverVer" "$PASS"
		fi

		if [ "$getUpdate" != "false" ]
		then
			printf "\n${BOLD}Do you want to continue with the update? (y/n)${CLEARFORMAT}  "
			read -r confirm
			case "$confirm" in
				y|Y)
					Update_File shared-jy.tar.gz
					Update_File YazFi_www.asp
					Update_File YazFi_networkmap.js
					Update_File README.md
					Update_File LICENSE
					Update_File "$SCRIPT_CONF"

					if ! Download_File "$SCRIPT_REPO" "${SCRIPT_NAME}.sh" "$SCRIPT_FPATH"
					then
						Print_Output true "$SCRIPT_NAME script file was NOT updated. Download failed." "$ERR"
						Clear_Lock ; return 1
					fi
					chmod 755 "$SCRIPT_FPATH"
					Print_Output true "$SCRIPT_NAME was successfully updated - restarting firewall to apply update" "$PASS"
					Set_Version_Custom_Settings local "$serverVer"
					Set_Version_Custom_Settings server "$serverVer"
					Clear_Lock
					service restart_firewall >/dev/null 2>&1
					PressEnter
					exec "$0"
					exit 0
				;;
				*)
					printf "\n"
					Clear_Lock
					return 1
				;;
			esac
		else
			Print_Output true "No updates available - latest is $localVers" "$WARN"
			Clear_Lock
		fi
	fi

	if [ "$1" = "force" ]
	then
		if ! Download_File "$SCRIPT_REPO" "${SCRIPT_NAME}.sh" "$SCRIPT_FPATH"
		then
			Print_Output true "$SCRIPT_NAME script file was NOT updated. Download failed." "$ERR"
			Clear_Lock ; return 1
		fi
		chmod 755 "$SCRIPT_FPATH"
		serverVer="$(grep '^readonly SCRIPT_VERSION=' "$SCRIPT_FPATH" | grep -m1 -oE "$scriptVersRegExp")"
		Print_Output true "Downloading latest version ($serverVer) of $SCRIPT_NAME" "$PASS"

		Update_File shared-jy.tar.gz
		Update_File YazFi_www.asp
		Update_File YazFi_networkmap.js
		Update_File README.md
		Update_File LICENSE
		Update_File "$SCRIPT_CONF"

        Print_Output true "$SCRIPT_NAME was successfully updated - restarting firewall to apply update" "$PASS"
		Set_Version_Custom_Settings local "$serverVer"
		Set_Version_Custom_Settings server "$serverVer"
		Clear_Lock
		service restart_firewall >/dev/null 2>&1
		if [ $# -lt 2 ] || [ -z "$2" ]
		then
			PressEnter
			exec "$0"
		elif [ "$2" = "unattended" ]
		then
			exec "$0" postupdate
		fi
		exit 0
	fi
}

##-------------------------------------##
## Added by Martinski W. [2026-Feb-18] ##
##-------------------------------------##
ScriptUpdateFromAMTM()
{
    if ! "$doScriptUpdateFromAMTM"
    then
        printf "Automatic script updates via AMTM are currently disabled.\n\n"
        return 1
    fi
    if [ $# -gt 0 ] && [ "$1" = "check" ]
    then return 0
    fi
    Update_Version force unattended
    return "$?"
}

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
Update_File()
{
	if [ "$1" = "YazFi_www.asp" ]
	then
		tempFileASP="${TEMP_DIR}/${1}.TMP.ASP" ; rm -f "$tempFileASP"
		if [ -s "${SCRIPT_DIR}/$1" ]
		then
			if ! Download_File "$SCRIPT_REPO" "$1" "$tempFileASP"
			then
				Print_Output true "The WebUI file [$1] was NOT updated. Download failed." "$ERR"
				return 1
			fi
			if ! diff -q "$tempFileASP" "${SCRIPT_DIR}/$1" >/dev/null 2>&1
			then
				Get_WebUI_Page "${SCRIPT_DIR}/$1"
				sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"
				rm -f "${SCRIPT_WEBPAGE_DIR}/$MyWebPage" 2>/dev/null
				mv -f "$tempFileASP" "${SCRIPT_DIR}/$1"
				chmod 644 "${SCRIPT_DIR}/$1"
				Print_Output true "New version of $1 was downloaded" "$PASS"
				Mount_WebUI
			fi
			rm -f "$tempFileASP"
		else
			if ! Download_File "$SCRIPT_REPO" "$1" "${SCRIPT_DIR}/$1"
			then
				Print_Output true "The WebUI file [$1] was NOT updated. Download failed." "$ERR"
				return 1
			fi
			Print_Output true "New version of $1 was downloaded" "$PASS"
			Mount_WebUI
		fi
	elif [ "$1" = "shared-jy.tar.gz" ]
	then
		tempFileMD5="${TEMP_DIR}/${1}.TMP.MD5" ; rm -f "$tempFileMD5"
		if ! Download_File "$SHARED_REPO" "${1}.md5" "$tempFileMD5"
		then
			Print_Output true "Download failed for shared archive file [$1]" "$ERR"
			return 1
		fi
		if [ ! -s "${SHARED_DIR}/${1}.md5" ] || \
		   [ "$(cat "${SHARED_DIR}/${1}.md5")" != "$(cat "$tempFileMD5")" ]
		then
			if ! Download_File "$SHARED_REPO" "$1" "${SHARED_DIR}/$1"
			then
				rm -f "$tempFileMD5"
				Print_Output true "Download failed for shared archive file [$1]" "$ERR"
				return 1
			fi
			mv -f "$tempFileMD5" "${SHARED_DIR}/${1}.md5"
			chmod 644 "${SHARED_DIR}/${1}.md5"
			tar -xzf "${SHARED_DIR}/$1" -C "$SHARED_DIR"
			rm -f "${SHARED_DIR}/$1"
			Print_Output true "New version of $1 was downloaded" "$PASS"
		else
			rm -f "$tempFileMD5"
		fi
	elif [ "$1" = "YazFi_networkmap.js" ]
	then
		tempFileJS="${TEMP_DIR}/${1}.TMP.JS" ; rm -f "$tempFileJS"
		if ! Download_File "$SCRIPT_REPO" "$1" "$tempFileJS"
		then
			Print_Output true "The Network Map JS source file [$1] was NOT updated. Download failed." "$ERR"
			return 1
		fi
		if ! grep -qF "$NETWORKMAP_MARKER" "$tempFileJS"
		then
			rm -f "$tempFileJS"
			Print_Output true "Downloaded file $1 failed validation" "$ERR"
			return 1
		fi
		if [ ! -s "${SCRIPT_DIR}/$1" ] || \
		   ! diff -q "${SCRIPT_DIR}/$1" "$tempFileJS" >/dev/null 2>&1
		then
			mv -f "$tempFileJS" "${SCRIPT_DIR}/$1"
			chmod 644 "${SCRIPT_DIR}/$1"
			Print_Output true "New version of $1 was downloaded" "$PASS"
			NetworkMap_WebUI remount 2>/dev/null
		else
			rm -f "$tempFileJS"
		fi
	elif [ "$1" = "README.md" ] || [ "$1" = "LICENSE" ]
	then
		tempFileDOC="${TEMP_DIR}/${1}.TMP.DOC" ; rm -f "$tempFileDOC"
		if Download_File "$SCRIPT_REPO" "$1" "$tempFileDOC" && \
		   ! diff -q "$tempFileDOC" "${SCRIPT_DIR}/$1" >/dev/null 2>&1
		then
			mv -f "$tempFileDOC" "${SCRIPT_DIR}/$1"
		fi
		rm -f "$tempFileDOC"
	elif [ "$1" = "$SCRIPT_CONF" ]
	then
		if ! grep -qE '^wl3[1-3]_.+' "$SCRIPT_CONF"
		then
			if Config_ADD_Download "$SCRIPT_CONF"
			then
				cat "${SCRIPT_CONF}.ADD.txt" >> "$SCRIPT_CONF"
				cp -fp "$SCRIPT_CONF" "${SCRIPT_CONF}.bak"
				rm -f "${SCRIPT_CONF}.ADD.txt"
			else
				Print_Output true "Could NOT update configuration file: $SCRIPT_CONF" "$ERR"
			fi
		fi
	else
		return 1
	fi
}

IP_Local()
{
	if echo "$1" | grep -qE '(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)'
	then
		return 0
	elif [ "$1" = "127.0.0.1" ]
	then
		return 0
	else
		return 1
	fi
}

IP_Router()
{
	if [ "$1" = "$LAN_IPaddr" ] || [ "$1" = "127.0.0.1" ]
	then
		return 0
	elif [ "$1" = "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")" ]
	then
		return 0
	else
		return 1
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Validate_IFACE_Enabled()
{
	IFACE_TEST="$(_NVRAM_Get_ "${1}_bss_enabled")"
	if ! Validate_Number '' "$IFACE_TEST" silent
	then IFACE_TEST=0
	fi
	[ "$IFACE_TEST" -eq 1 ] && return 0

	if [ $# -lt 2 ] || [ -z "$2" ]
	then
		Print_Output false "$1 - Interface NOT enabled/configured in Web GUI (Guest Network menu)" "$ERR"
	fi
	return 1
}

##----------------------------------------##
## Modified by Martinski W. [2026-Aug-20] ##
##----------------------------------------##
Validate_IFACE_Exists()
{
	if echo "$IFACELIST" | grep -qw "$1"
	then return 0
	fi
	if [ $# -lt 2 ] || [ -z "$2" ]
	then
		Print_Output false "$1 - Interface NOT supported on this router" "$ERR"
	fi
	return 1
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
Validate_IFACE_Support()
{
	if echo "$IFACELIST_ORIG" | grep -qw "$1"
	then return 0
	fi
	if [ $# -lt 2 ] || [ -z "$2" ]
	then
		Print_Output false "$1 - Interface NOT supported on this router" "$ERR"
	fi
	return 1
}

Validate_IP()
{
	if expr "$2" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null
	then
		for i in 1 2 3 4
		do
			if [ "$(echo "$2" | cut -d. -f$i)" -gt 255 ]
			then
				Print_Output false "$1 - Octet $i ($(echo "$2" | cut -d. -f$i)) - is invalid, must be less than 255" "$ERR"
				return 1
			fi
		done

		if [ "$3" != "DNS" ]
		then
			if IP_Local "$2"
			then
				return 0
			else
				Print_Output false "$1 - $2 - Non-local IP address block used" "$ERR"
				return 1
			fi
		else
			return 0
		fi
	else
		Print_Output false "$1 - $2 - is NOT a valid IPv4 address, valid format is 1.2.3.4" "$ERR"
		return 1
	fi
}

Validate_Number()
{
	if [ "$2" -eq "$2" ] 2>/dev/null
	then
		return 0
	else
		formatted="$(echo "$1" | sed -e 's/|/ /g')"
		if [ -z "$3" ]; then
			Print_Output false "$formatted - $2 is not a number" "$ERR"
		fi
		return 1
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2022-Dec-05] ##
##----------------------------------------##
Validate_DHCP()
{
	if ! Validate_Number "$1" "$2"; then
		return 1
	elif ! Validate_Number "$1" "$3"; then
		return 1
	fi

	if [ "$2" -gt "$3" ] || { [ "$2" -lt 2 ] || [ "$2" -gt 253 ]; } || { [ "$3" -lt 3 ] || [ "$3" -gt 254 ]; }
	then
		Print_Output false "$1 - $2 to $3 - both numbers must be between 2 and 254, $2 must be less than $3" "$ERR"
		return 1
	else
		return 0
	fi
}

##----------------------------------------------##
## Added/modified by Martinski W. [2023-Jan-30] ##
##----------------------------------------------##
# The DHCP Lease Time values can be given in:
# seconds, minutes, hours, days, or weeks.
# Single '0' or 'I' indicates "infinite" value.
#------------------------------------------------#
Validate_DHCP_LeaseTime()
{
	timeUnits="X"  timeFactor=1  timeNumber="$2"

	if [ "$2" = "0" ] || [ "$2" = "$InfiniteLeaseTimeTag" ]
	then return 0 ; fi

	if echo "$2" | grep -q "^0.*"
	then
		Print_Output false "$1 - $2 is not a valid setting." "$ERR"
		return 1
	fi

	if echo "$2" | grep -q "^[0-9]\{1,7\}$"
	then
		timeUnits="s"
		timeNumber="$2"
	elif echo "$2" | grep -q "^[0-9]\{1,6\}[smhdw]\{1\}$"
	then
		timeUnits="$(echo "$2" | awk '{print substr($0,length($0),1)}')"
		timeNumber="$(echo "$2" | awk '{print substr($0,0,length($0)-1)}')"
	fi

	case "$timeUnits" in
		s) timeFactor=1 ;;
		m) timeFactor=60 ;;
		h) timeFactor=3600 ;;
		d) timeFactor=86400 ;;
		w) timeFactor=604800 ;;
	esac

	if ! Validate_Number "$1" "$timeNumber"
	then return 1 ; fi

	timeValue="$((timeNumber * timeFactor))"

	if [ "$timeValue" -lt "$MinDHCPLeaseTime" ] || [ "$timeValue" -gt "$MaxDHCPLeaseTime" ]
	then
		Print_Output false "$1 - $timeValue - must be between $MinDHCPLeaseTime and $MaxDHCPLeaseTime in seconds." "$ERR"
		return 1
	else
		return 0
	fi
}

Validate_VPNClientNo()
{
	if ! Validate_Number "$1" "$2"; then
		return 1
	fi

	if [ "$2" -lt 1 ] || [ "$2" -gt 5 ]
	then
		Print_Output false "$1 - $2 - must be between 1 and 5" "$ERR"
		return 1
	else
		return 0
	fi
}

Validate_TrueFalse()
{
	case "$2" in
		true|TRUE|false|FALSE)
			return 0
		;;
		*)
			Print_Output false "$1 - $2 - must be either true or false" "$ERR"
			return 1
		;;
	esac
}

Validate_String()
{
		if expr "$1" : '[a-zA-Z0-9][a-zA-Z0-9]*$' >/dev/null; then
			return 0
		else
			Print_Output false "String contains non-alphanumeric characters, these will be removed" "$ERR"
			return 1
		fi
}

##----------------------------------------##
## Modified by Martinski W. [2023-Dec-22] ##
##----------------------------------------##
Conf_FromSettings()
{
	SETTINGSFILE="${JFFS_ADDONS}/custom_settings.txt"
	TMPFILE="/tmp/yazfi_settings.txt"
	if [ -f "$SETTINGSFILE" ]
	then
		if [ "$(grep "yazfi_" $SETTINGSFILE | grep -v "version" -c)" -gt 0 ]
		then
			Print_Output true "Updated settings from WebUI found, merging into $SCRIPT_CONF" "$PASS"
			cp -fp "$SCRIPT_CONF" "${SCRIPT_CONF}.bak"
			grep "yazfi_" "$SETTINGSFILE" | grep -v "version" > "$TMPFILE"
			sed -i "s/yazfi_//g;s/ /=/g" "$TMPFILE"
			while IFS='' read -r line || [ -n "$line" ]
			do
				SETTINGNAME="$(echo "$line" | cut -f1 -d'=' | awk 'BEGIN{FS="_"}{ print $1 "_" toupper($2) }')"
				SETTINGVALUE="$(echo "$line" | cut -f2 -d'=')"
				echo "$SETTINGVALUE" | grep -qE "^(true|false|I|[0-9][0-9.]*[smhdw]?)$" && \
				sed -i "s/$SETTINGNAME=.*/$SETTINGNAME=$SETTINGVALUE/" "$SCRIPT_CONF"
			done < "$TMPFILE"
			grep 'yazfi_version' "$SETTINGSFILE" > "$TMPFILE"
			sed -i "\\~yazfi_~d" "$SETTINGSFILE"
			mv -f "$SETTINGSFILE" "${SETTINGSFILE}.bak"
			cat "${SETTINGSFILE}.bak" "$TMPFILE" > "$SETTINGSFILE"
			rm -f "$TMPFILE" "${SETTINGSFILE}.bak"
			Print_Output true "Merge of updated settings from WebUI completed successfully" "$PASS"
		else
			Print_Output false "No updated settings from WebUI found, no merge into $SCRIPT_CONF necessary" "$PASS"
		fi
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2022-Dec-07] ##
##----------------------------------------##
Conf_FixBlanks()
{
	if ! Conf_Exists
	then
		Config_Download "$SCRIPT_CONF"
		Clear_Lock
		return 1
	fi
	NetworkMap_Ensure_Config

	. "$SCRIPT_CONF"
	cp -fp "$SCRIPT_CONF" "${SCRIPT_CONF}.bak"

	for IFACEBLANK in $IFACELIST_FULL
	do
		IFACETMPBLANK="$(Get_Iface_Var "$IFACEBLANK")"
		IPADDRTMPBLANK=""

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_IPADDR")" ]
		then
			IPADDRTMPBLANK="192.168.0"

			COUNTER=0
			until [ "$(grep -o "$IPADDRTMPBLANK" $SCRIPT_CONF | wc -l)" -eq 0 ] && [ "$(ifconfig -a | grep -o "$IPADDRTMPBLANK" | wc -l )" -eq 0 ]
			do
				IPADDRTMPBLANK="192.168.$COUNTER"
				COUNTER="$((COUNTER + 1))"
			done

			sed -i -e "s/${IFACETMPBLANK}_IPADDR=/${IFACETMPBLANK}_IPADDR=${IPADDRTMPBLANK}.0/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_IPADDR is blank, setting to next available subnet" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_DHCPSTART")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_DHCPSTART=/${IFACETMPBLANK}_DHCPSTART=2/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_DHCPSTART is blank, setting to 2" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_DHCPEND")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_DHCPEND=/${IFACETMPBLANK}_DHCPEND=254/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_DHCPEND is blank, setting to 254" "$WARN"
		fi

		##----------------------------------------##
		## Modified by Martinski W. [2022-Dec-23] ##
		##----------------------------------------##
		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_DHCPLEASE")" ] || \
		   ! grep -q "${IFACETMPBLANK}_DHCPLEASE=" "$SCRIPT_CONF"
		then
			DHCP_LEASE_VAL="$(_NVRAM_Get_ dhcp_lease)"
			if grep -q "${IFACETMPBLANK}_DHCPLEASE=" "$SCRIPT_CONF"
			then
				OUTmsg="is blank, setting to $DHCP_LEASE_VAL seconds"
				sed -i -e "s/${IFACETMPBLANK}_DHCPLEASE=/${IFACETMPBLANK}_DHCPLEASE=${DHCP_LEASE_VAL}/" "$SCRIPT_CONF"
			else
				OUTmsg="is not found."
				NUMLINE="$(grep -n "${IFACETMPBLANK}_DHCPEND=" "$SCRIPT_CONF" | awk -F ':' '{print $1}')"
				if [ -n "$NUMLINE" ]
				then
					OUTmsg="is not found, setting to $DHCP_LEASE_VAL seconds"
					sed -i "$((NUMLINE + 1)) i ${IFACETMPBLANK}_DHCPLEASE=${DHCP_LEASE_VAL}" "$SCRIPT_CONF"
				fi
			fi
			Print_Output false "${IFACETMPBLANK}_DHCPLEASE ${OUTmsg}" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_DNS1")" ]
		then
			if [ -n "$(eval echo '$'"${IFACETMPBLANK}_IPADDR")" ]
			then
				sed -i -e "s/${IFACETMPBLANK}_DNS1=/${IFACETMPBLANK}_DNS1=$(eval echo '$'"${IFACETMPBLANK}_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")/" "$SCRIPT_CONF"
				Print_Output false "${IFACETMPBLANK}_DNS1 is blank, setting to $(eval echo '$'"${IFACETMPBLANK}_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")" "$WARN"
			else
				sed -i -e "s/${IFACETMPBLANK}_DNS1=/${IFACETMPBLANK}_DNS1=$IPADDRTMPBLANK.$(echo "$LAN_IPaddr" | cut -f4 -d".")/" "$SCRIPT_CONF"
				Print_Output false "${IFACETMPBLANK}_DNS1 is blank, setting to $IPADDRTMPBLANK.$(echo "$LAN_IPaddr" | cut -f4 -d".")" "$WARN"
			fi
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_DNS2")" ]
		then
			if [ -n "$(eval echo '$'"${IFACETMPBLANK}_IPADDR")" ]
			then
				sed -i -e "s/${IFACETMPBLANK}_DNS2=/${IFACETMPBLANK}_DNS2=$(eval echo '$'"${IFACETMPBLANK}_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")/" "$SCRIPT_CONF"
				Print_Output false "${IFACETMPBLANK}_DNS2 is blank, setting to $(eval echo '$'"${IFACETMPBLANK}_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")" "$WARN"
			else
				sed -i -e "s/${IFACETMPBLANK}_DNS2=/${IFACETMPBLANK}_DNS2=$IPADDRTMPBLANK.$(echo "$LAN_IPaddr" | cut -f4 -d".")/" "$SCRIPT_CONF"
				Print_Output false "${IFACETMPBLANK}_DNS2 is blank, setting to $IPADDRTMPBLANK.$(echo "$LAN_IPaddr" | cut -f4 -d".")" "$WARN"
			fi
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_FORCEDNS")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_FORCEDNS=/${IFACETMPBLANK}_FORCEDNS=false/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_FORCEDNS is blank, setting to false" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_ALLOWINTERNET")" ]
		then
			ALLOWINTERNETTMP="true"
			sed -i -e "s/${IFACETMPBLANK}_ALLOWINTERNET=/${IFACETMPBLANK}_ALLOWINTERNET=true/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_ALLOWINTERNET is blank, setting to true" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_REDIRECTALLTOVPN")" ]
		then
			REDIRECTTMP="false"
			sed -i -e "s/${IFACETMPBLANK}_REDIRECTALLTOVPN=/${IFACETMPBLANK}_REDIRECTALLTOVPN=false/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_REDIRECTALLTOVPN is blank, setting to false" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_VPNCLIENTNUMBER")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_VPNCLIENTNUMBER=/${IFACETMPBLANK}_VPNCLIENTNUMBER=1/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_VPNCLIENTNUMBER is blank, setting to 1" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_TWOWAYTOGUEST")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_TWOWAYTOGUEST=/${IFACETMPBLANK}_TWOWAYTOGUEST=false/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_TWOWAYTOGUEST is blank, setting to false" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_TWOWAYTOGUEST_MODE")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_TWOWAYTOGUEST_MODE=/${IFACETMPBLANK}_TWOWAYTOGUEST_MODE=NAT/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_TWOWAYTOGUEST_MODE is blank, setting to NAT" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_ONEWAYTOGUEST")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_ONEWAYTOGUEST=/${IFACETMPBLANK}_ONEWAYTOGUEST=false/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_ONEWAYTOGUEST is blank, setting to false" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_ONEWAYTOGUEST_MODE")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_ONEWAYTOGUEST_MODE=/${IFACETMPBLANK}_ONEWAYTOGUEST_MODE=NAT/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_ONEWAYTOGUEST_MODE is blank, setting to NAT" "$WARN"
		fi

		if [ -z "$(eval echo '$'"${IFACETMPBLANK}_CLIENTISOLATION")" ]
		then
			sed -i -e "s/${IFACETMPBLANK}_CLIENTISOLATION=/${IFACETMPBLANK}_CLIENTISOLATION=false/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMPBLANK}_CLIENTISOLATION is blank, setting to false" "$WARN"
		fi
	done

	if ! diff -q "$SCRIPT_CONF" "${SCRIPT_CONF}.bak" >/dev/null 2>&1
	then . "$SCRIPT_CONF"
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2024-Jan-06] ##
##----------------------------------------##
Conf_Validate()
{
	GUESTNET_ENABLED=false

	Conf_FixBlanks

	for IFACE in $IFACELIST_FULL
	do
		IFACETMP="$(Get_Iface_Var "$IFACE")"
		IPADDRTMP=""
		REDIRECTTMP=""
		IFACE_PASS=true
		IFACE_ENABLED=""

		if [ -z "$(eval echo '$'"${IFACETMP}_ENABLED")" ]
		then
			IFACE_ENABLED=false
			sed -i -e "s/${IFACETMP}_ENABLED=/${IFACETMP}_ENABLED=false/" "$SCRIPT_CONF"
			Print_Output false "${IFACETMP}_ENABLED is blank, setting to false" "$WARN"
		elif ! Validate_TrueFalse "${IFACETMP}_ENABLED" "$(eval echo '$'"${IFACETMP}_ENABLED")"
		then
			IFACE_PASS=false ; IFACE_ENABLED=false
		else
			IFACE_ENABLED="$(eval echo '$'"${IFACETMP}_ENABLED")"
		fi

		if ! Validate_IFACE_Support "$IFACE" silent
		then
			IFACE_PASS=false
			"$IFACE_ENABLED" && \
			Print_Output false "Interface $IFACE is NOT supported on this router" "$ERR"
		#
		elif ! Validate_IFACE_Enabled "$IFACE" silent
		then
			IFACE_PASS=false
			Print_Output false "Interface $IFACE is NOT enabled on this router" "$WARN"
        #
		elif [ "$IFACE_ENABLED" = "false" ]
		then
			IFACE_PASS=false
			Print_Output false "Interface $IFACE is NOT enabled in $SCRIPT_NAME configuration" "$WARN"
		else
			GUESTNET_ENABLED=true

				if [ "$(eval echo '$'"${IFACETMP}_ENABLED")" = "true" ]
				then
					if ! Validate_IP "${IFACETMP}_IPADDR" "$(eval echo '$'"${IFACETMP}_IPADDR")"
					then
						IFACE_PASS=false
					else
						IPADDRTMP="$(eval echo '$'"${IFACETMP}_IPADDR" | cut -f1-3 -d".")"

						if [ "$(eval echo '$'"${IFACETMP}_IPADDR" | cut -f4 -d".")" -ne 0 ]
						then
							sed -i -e "s/${IFACETMP}_IPADDR=$(eval echo '$'"${IFACETMP}_IPADDR")/${IFACETMP}_IPADDR=$IPADDRTMP.0/" "$SCRIPT_CONF"
							Print_Output false "${IFACETMP}_IPADDR setting last octet to 0" "$WARN"
						fi

						if [ "$(ifconfig -a | grep -o "inet addr:$IPADDRTMP.$(echo "$LAN_IPaddr" | cut -f4 -d'.')"  | sed 's/inet addr://' | wc -l )" -gt 1 ]
						then
							Print_Output false "${IFACETMP}_IPADDR ($(eval echo '$'"${IFACETMP}_IPADDR")) has been used for another interface already" "$ERR"
							IFACE_PASS=false
						fi
					fi

					if [ -n "$(eval echo '$'"${IFACETMP}_DHCPSTART")" ] && [ -n "$(eval echo '$'"${IFACETMP}_DHCPEND")" ]
					then
						if ! Validate_DHCP "${IFACETMP}_DHCPSTART|and|${IFACETMP}_DHCPEND" "$(eval echo '$'"${IFACETMP}_DHCPSTART")" "$(eval echo '$'"${IFACETMP}_DHCPEND")"; then
						IFACE_PASS=false
						fi
					fi

					##-------------------------------------##
					## Added by Martinski W. [2022-Dec-01] ##
					##-------------------------------------##
					if [ -n "$(eval echo '$'"${IFACETMP}_DHCPLEASE")" ]
					then
						if ! Validate_DHCP_LeaseTime "${IFACETMP}_DHCPLEASE" "$(eval echo '$'"${IFACETMP}_DHCPLEASE")"
						then
							IFACE_PASS=false
						fi
					fi

					if ! Validate_TrueFalse "${IFACETMP}_FORCEDNS" "$(eval echo '$'"${IFACETMP}_FORCEDNS")"
					then
						IFACE_PASS=false
					else
						if [ "$(eval echo '$'"${IFACETMP}_FORCEDNS")" = "true" ]
						then
							Print_Output false "$IFACE has FORCEDNS enabled, setting DNS2 to match DNS1..." "$WARN"
							sed -i -e "s/${IFACETMP}_DNS2=.*/${IFACETMP}_DNS2=$(eval echo '$'"${IFACETMP}_DNS1")/" "$SCRIPT_CONF"
						fi
					fi

					if ! Validate_IP "${IFACETMP}_DNS1" "$(eval echo '$'"${IFACETMP}_DNS1")" "DNS"
					then
						IFACE_PASS=false
					fi

					if ! Validate_IP "${IFACETMP}_DNS2" "$(eval echo '$'"${IFACETMP}_DNS2")" "DNS"
					then
						IFACE_PASS=false
					fi

					if ! Validate_TrueFalse "${IFACETMP}_ALLOWINTERNET" "$(eval echo '$'"${IFACETMP}_ALLOWINTERNET")"
					then
						ALLOWINTERNETTMP="true"
						IFACE_PASS=false
					else
						ALLOWINTERNETTMP="$(eval echo '$'"${IFACETMP}_ALLOWINTERNET")"
					fi

					if [ "$ALLOWINTERNETTMP" = "false" ] && ! IP_Local "$(eval echo '$'"${IFACETMP}_DNS1")"
					then
						Print_Output false "$IFACE has internet access disabled and a non-local IP has been set for DNS1" "$ERR"
						IFACE_PASS=false
					fi

					if [ "$ALLOWINTERNETTMP" = "false" ] && ! IP_Local "$(eval echo '$'"${IFACETMP}_DNS2")"
					then
						Print_Output false "$IFACE has internet access disabled and a non-local IP has been set for DNS2" "$ERR"
						IFACE_PASS=false
					fi

					if ! Validate_TrueFalse "${IFACETMP}_REDIRECTALLTOVPN" "$(eval echo '$'"${IFACETMP}_REDIRECTALLTOVPN")"
					then
						REDIRECTTMP="false"
						IFACE_PASS=false
					else
						REDIRECTTMP="$(eval echo '$'"${IFACETMP}_REDIRECTALLTOVPN")"
					fi

					if [ "$REDIRECTTMP" = "true" ] && [ "$ALLOWINTERNETTMP" = "true" ]
					then
						if ! Validate_VPNClientNo "${IFACETMP}_VPNCLIENTNUMBER" "$(eval echo '$'"${IFACETMP}_VPNCLIENTNUMBER")"
						then
							IFACE_PASS=false
						else
							if [ "$(_NVRAM_Get_ vpn_client"$(eval echo '$'"${IFACETMP}_VPNCLIENTNUMBER")"_rgw)" -ne 2 ]
							then
								Print_Output false "VPN Client $(eval echo '$'"${IFACETMP}_VPNCLIENTNUMBER") is not configured for Policy Routing, enabling it..." "$WARN"
								nvram set vpn_client"$(eval echo '$'"${IFACETMP}_VPNCLIENTNUMBER")"_rgw=2
								nvram commit
							fi
						fi
					fi

					if ! Validate_TrueFalse "${IFACETMP}_TWOWAYTOGUEST" "$(eval echo '$'"${IFACETMP}_TWOWAYTOGUEST")"
					then
						IFACE_PASS=false
					fi

					if ! Validate_TrueFalse "${IFACETMP}_ONEWAYTOGUEST" "$(eval echo '$'"${IFACETMP}_ONEWAYTOGUEST")"
					then
						IFACE_PASS=false
					fi

					if [ "$(eval echo '$'"${IFACETMP}_ONEWAYTOGUEST")" = "true" ] && [ "$(eval echo '$'"${IFACETMP}_TWOWAYTOGUEST")" = "true" ]
					then
						Print_Output false "$(eval echo '$'"${IFACETMP}_ONEWAYTOGUEST") & $(eval echo '$'"${IFACETMP}_TWOWAYTOGUEST") cannot both be true" "$ERR"
						IFACE_PASS=false
					fi

					if ! Validate_TrueFalse "${IFACETMP}_CLIENTISOLATION" "$(eval echo '$'"${IFACETMP}_CLIENTISOLATION")"
					then
						IFACE_PASS=false
					fi

					if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.1)" ]
					then
						if [ "$ROUTER_MODEL" = "RT-AX88U" ] || [ "$ROUTER_MODEL" = "RT-AX3000" ]
						then
							sed -i -e "s/${IFACETMP}_CLIENTISOLATION=true/${IFACETMP}_CLIENTISOLATION=false/" "$SCRIPT_CONF"
						fi
					fi

					if [ "$IFACE_PASS" = "true" ]
					then
						Print_Output false "$IFACE passed validation" "$PASS"
					fi
				fi
		fi

		if [ "$IFACE_PASS" = "false" ] && echo "$IFACELIST" | grep -qw "$IFACE"
		then
			IFACELIST="$(echo "$IFACELIST" | sed 's/'"$IFACE"'//;s/  / /')"
			if [ "$IFACE_ENABLED" = "false" ]
			then
			    Print_Output false "$IFACE is DISABLED, removing from list" "$ERR"
			else
			    Print_Output false "$IFACE failed validation, removing from list" "$CRIT"
			fi
		fi
	done
	IFACELIST="$(echo "$IFACELIST" | sed 's/^[[:blank:]]\+//;s/[[:blank:]]\+$//')"

	if [ "$GUESTNET_ENABLED" = "false" ]
	then
		Print_Output true "No $SCRIPT_NAME Guest Networks are enabled in the configuration file!" "$CRIT"
	fi

	return 0
}

Create_Dirs()
{
	if [ ! -d "$SCRIPT_DIR" ]; then
		mkdir -p "$SCRIPT_DIR"
	fi

	if [ ! -d "$USER_SCRIPT_DIR" ]; then
		mkdir -p "$USER_SCRIPT_DIR"
	fi

	if [ ! -d "$SCRIPT_WEBPAGE_DIR" ]; then
		mkdir -p "$SCRIPT_WEBPAGE_DIR"
	fi

	if [ ! -d "$SCRIPT_WEB_DIR" ]; then
		mkdir -p "$SCRIPT_WEB_DIR"
	fi

	if [ ! -d "$SHARED_DIR" ]; then
		mkdir -p "$SHARED_DIR"
	fi
}

Create_Symlinks()
{
	rm -f "$SCRIPT_WEB_DIR/"* 2>/dev/null

	ln -s "$SCRIPT_DIR/config"  "$SCRIPT_WEB_DIR/config.htm" 2>/dev/null
	ln -s "$SCRIPT_DIR/.connectedclients" "$SCRIPT_WEB_DIR/connectedclients.htm" 2>/dev/null

	if [ ! -d "$SHARED_WEB_DIR" ]; then
		ln -s "$SHARED_DIR" "$SHARED_WEB_DIR" 2>/dev/null
	fi
}

##---------------------------------------##
## Added by ExtremeFiretop [2026-Jul-02] ##
##---------------------------------------##
NetworkMap_Ensure_Config()
{
	[ -s "$SCRIPT_CONF" ] || return 0
	if ! grep -q '^YAZFI_NETWORKMAP_CLIENTS=' "$SCRIPT_CONF"
	then
		cat >> "$SCRIPT_CONF" <<'EOF_NETWORKMAP_CONFIG'

# Add enabled YazFi clients to the native ASUS Network Map client list.
# This is an experimental WebUI-only integration (true/false).
YAZFI_NETWORKMAP_CLIENTS=true
EOF_NETWORKMAP_CONFIG
	fi
}

NetworkMap_Config_Enabled()
{
	NetworkMap_Ensure_Config
	local YAZFI_NETWORKMAP_CLIENTS="false"
	[ -s "$SCRIPT_CONF" ] && . "$SCRIPT_CONF"
	case "$YAZFI_NETWORKMAP_CLIENTS" in
		true|TRUE) return 0 ;;
		*) return 1 ;;
	esac
}

NetworkMap_JSON_Escape()
{
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

##----------------------------------------##
## Modified by Martinski W. [2026-Jul-29] ##
##----------------------------------------##
NetworkMap_Generate_JSON()
{
	local TMPJSON FIRST IFACE IFACETAG IFADDR RADIO GUEST_INDEX ISWL
	local MAC IP LEASE LEASE_IP NAME RSSI
	local STAINFO CURTX CURRX CONNECTED WLCONNECTTIME
	local MAC_UPPER JMAC JIP JNAME JIFACE
	local JCURTX JCURRX JWLCONNECTTIME

	mkdir -p "$SCRIPT_WEB_DIR" || return 1
	TMPJSON="${NETWORKMAP_JSON}.$$"
	printf '[' > "$TMPJSON" || return 1
	FIRST=1

	if [ -s "$SCRIPT_CONF" ]
	then
		. "$SCRIPT_CONF"
		for IFACE in $IFACELIST_ORIG
		do
			IFACETAG="$(Get_Iface_Var "$IFACE")"
			[ "$(eval echo '$'"${IFACETAG}_ENABLED")" = "true" ] || continue

			IFADDR="$(ip -4 addr show dev "$IFACE" 2>/dev/null | awk '/inet / { print $2; exit }')"
			[ -z "$IFADDR" ] && continue

			RADIO="${IFACE%%.*}"
			RADIO="${RADIO#wl}"
			GUEST_INDEX="${IFACE#*.}"
			case "$RADIO" in ''|*[!0-9]*) continue ;; esac
			case "$GUEST_INDEX" in ''|*[!0-9]*) GUEST_INDEX=1 ;; esac
			ISWL="$((RADIO + 1))"

			for MAC in $(wl -i "$IFACE" assoclist 2>/dev/null | awk -F' ' '{print $2}')
			do
				if ! echo "$MAC" | grep -qE "^${MACaddr_RegExp}$"
				then continue
				fi

				IP="$(awk -v m="$MAC" -v d="$IFACE" '
					tolower($4) == tolower(m) && $6 == d && $3 == "0x2" { print $1; exit }
				' /proc/net/arp 2>/dev/null)"

				LEASE="$(awk -v m="$MAC" '
					tolower($2) == tolower(m) { line=$0 }
					END { print line }
				' /var/lib/misc/dnsmasq.leases 2>/dev/null)"
				LEASE_IP="$(printf '%s\n' "$LEASE" | awk '{ print $3 }')"
				NAME="$(printf '%s\n' "$LEASE" | awk '{ print $4 }')"
				[ -n "$IP" ] || IP="$LEASE_IP"

				if [ -z "$IP" ]
				then
					IP="$(ip neigh show dev "$IFACE" 2>/dev/null | awk -v m="$MAC" '
						tolower($5) == tolower(m) { print $1; exit }
					')"
				fi
				[ -z "$IP" ] && continue

				if [ -z "$NAME" ] || [ "$NAME" = "*" ]
				then NAME="$MAC"
				fi
				NAME="$(printf '%s' "$NAME" | sed 's/[^A-Za-z0-9._ -]/_/g')"

				RSSI="$(wl -i "$IFACE" rssi "$MAC" 2>/dev/null | awk 'NR == 1 { print $1 }')"
				case "$RSSI" in
					-[0-9]*|[0-9]*) ;;
					*) RSSI="-99" ;;
				esac

				STAINFO="$(wl -i "$IFACE" sta_info "$MAC" 2>/dev/null)"

				CURTX="$(printf '%s\n' "$STAINFO" | awk '
					/rate of last tx pkt/ {
						printf "%.1f", $6 / 1000
						exit
					}
				')"

				CURRX="$(printf '%s\n' "$STAINFO" | awk '
					/rate of last rx pkt/ {
						printf "%.1f", $6 / 1000
						exit
					}
				')"

				CONNECTED="$(printf '%s\n' "$STAINFO" | awk '
					/in network/ {
						print $3
						exit
					}
				')"

				case "$CONNECTED" in
					''|*[!0-9]*)
						WLCONNECTTIME="00:00:00"
					;;
					*)
						WLCONNECTTIME="$(printf '%02d:%02d:%02d' \
							$((CONNECTED / 3600)) \
							$(((CONNECTED % 3600) / 60)) \
							$((CONNECTED % 60)))"
					;;
				esac

				MAC_UPPER="$(printf '%s' "$MAC" | tr '[:lower:]' '[:upper:]')"
				JMAC="$(NetworkMap_JSON_Escape "$MAC_UPPER")"
				JIP="$(NetworkMap_JSON_Escape "$IP")"
				JNAME="$(NetworkMap_JSON_Escape "$NAME")"
				JIFACE="$(NetworkMap_JSON_Escape "$IFACE")"
				JCURTX="$(NetworkMap_JSON_Escape "$CURTX")"
				JCURRX="$(NetworkMap_JSON_Escape "$CURRX")"
				JWLCONNECTTIME="$(NetworkMap_JSON_Escape "$WLCONNECTTIME")"

				[ "$FIRST" -eq 1 ] || printf ',' >> "$TMPJSON"
				FIRST=0
				printf '{"mac":"%s","ip":"%s","name":"%s","isWL":"%s","isGN":"%s","rssi":"%s","iface":"%s","curTx":"%s","curRx":"%s","wlConnectTime":"%s"}' \
					"$JMAC" \
					"$JIP" \
					"$JNAME" \
					"$ISWL" \
					"$GUEST_INDEX" \
					"$RSSI" \
					"$JIFACE" \
					"$JCURTX" \
					"$JCURRX" \
					"$JWLCONNECTTIME" >> "$TMPJSON"
			done
		done
	fi

	printf ']\n' >> "$TMPJSON"
	chmod 644 "$TMPJSON"
	mv -f "$TMPJSON" "$NETWORKMAP_JSON"
}

NetworkMap_Daemon_Running()
{
	[ -s "$NETWORKMAP_PIDFILE" ] || return 1
	local PID="$(cat "$NETWORKMAP_PIDFILE" 2>/dev/null)"
	[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}

NetworkMap_Daemon()
{
	case "$1" in
		start)
			NetworkMap_Config_Enabled || { NetworkMap_Daemon stop; return 0; }
			NetworkMap_Daemon_Running && return 0
			rm -f "$NETWORKMAP_PIDFILE"
			$SCRIPT_FPATH networkmap daemon >/dev/null 2>&1 &
			echo "$!" > "$NETWORKMAP_PIDFILE"
		;;
		stop)
			if NetworkMap_Daemon_Running
			then
				kill "$(cat "$NETWORKMAP_PIDFILE")" 2>/dev/null
			fi
			rm -f "$NETWORKMAP_PIDFILE"
		;;
		run)
			echo "$$" > "$NETWORKMAP_PIDFILE"
			trap '[ "$(cat "$NETWORKMAP_PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$NETWORKMAP_PIDFILE"' EXIT
			trap 'exit 0' INT TERM
			renice 15 $$
			while NetworkMap_Config_Enabled
			do
				NetworkMap_Generate_JSON
				sleep "$NETWORKMAP_REFRESH_SECS"
			done
			renice 0 $$
			printf '[]\n' > "$NETWORKMAP_JSON"
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2026-Jul-29] ##
##----------------------------------------##
NetworkMap_WebUI()
{
	case "$1" in
		start|remount)
			if ! NetworkMap_Config_Enabled
			then
				NetworkMap_WebUI stop
				return 0
			fi
			if [ ! -s "$NETWORKMAP_SOURCE_JS" ]
			then
				Print_Output true "Network Map JS source missing" "$ERR"
				return 1
			fi
			if [ ! -s "$NETWORKMAP_TARGET_JS" ]
			then
				Print_Output true "Network Map JS target missing" "$ERR"
				return 1
			fi
			if grep -q "$NETWORKMAP_MARKER" "$NETWORKMAP_TARGET_JS"
			then
				umount "$NETWORKMAP_TARGET_JS" 2>/dev/null
			fi
			cp -fp "$NETWORKMAP_TARGET_JS" "$NETWORKMAP_BASE_JS" || return 1
			if grep -q "$NETWORKMAP_MARKER" "$NETWORKMAP_BASE_JS"
			then
				Print_Output true "Network Map patch marker remained after unmount" "$WARN"
				return 1
			fi

			awk '
				BEGIN { patched=0 }
				{
					print
					if (!patched && $0 ~ /^[[:space:]]*function[[:space:]]+genClientList[[:space:]]*\(\)[[:space:]]*\{/) {
						print "yazfiMergeIntoOriginData();"
						patched=1
					}
				}
				END { if (!patched) exit 42 }
			' "$NETWORKMAP_BASE_JS" > "$NETWORKMAP_PATCH_JS" || \
			{
				Print_Output true "Unable to locate genClientList() in client_function.js" "$WARN"
				rm -f "$NETWORKMAP_PATCH_JS"
				return 1
			}

			cat "$NETWORKMAP_SOURCE_JS" >> "$NETWORKMAP_PATCH_JS" || return 1
			chmod 644 "$NETWORKMAP_PATCH_JS"
			mount -o bind "$NETWORKMAP_PATCH_JS" "$NETWORKMAP_TARGET_JS" || return 1
			# Restart the daemon so it loads the current YazFi.sh functions #
			NetworkMap_Daemon stop
			sleep 1
			NetworkMap_Generate_JSON
			NetworkMap_Daemon start
			Print_Output true "Native Network Map integration active" "$PASS"
		;;
		stop)
			NetworkMap_Daemon stop
			if grep -q "$NETWORKMAP_MARKER" "$NETWORKMAP_TARGET_JS" 2>/dev/null
			then
				umount "$NETWORKMAP_TARGET_JS" 2>/dev/null
			fi
			rm -f "$NETWORKMAP_JSON" "$NETWORKMAP_PATCH_JS" "$NETWORKMAP_BASE_JS"
		;;
	esac
}

NetworkMap_Apply()
{
	if NetworkMap_Config_Enabled
	then
		NetworkMap_WebUI start || \
		Print_Output true "Unable to enable native Network Map integration" "$WARN"
	else
		NetworkMap_WebUI stop
	fi
}

NetworkMap_Set_Enabled()
{
	NetworkMap_Ensure_Config

	case "$1" in
		true|false) ;;
		*) return 1 ;;
	esac

	if grep -q '^YAZFI_NETWORKMAP_CLIENTS=' "$SCRIPT_CONF" 2>/dev/null
	then
		sed -i "s/^YAZFI_NETWORKMAP_CLIENTS=.*/YAZFI_NETWORKMAP_CLIENTS=$1/" "$SCRIPT_CONF"
	else
		printf '\nYAZFI_NETWORKMAP_CLIENTS=%s\n' "$1" >> "$SCRIPT_CONF"
	fi
}

NetworkMap_Status()
{
	if NetworkMap_Config_Enabled
	then NM_ENABLED=true
	else NM_ENABLED=false
	fi
	if grep -q "$NETWORKMAP_MARKER" "$NETWORKMAP_TARGET_JS" 2>/dev/null
	then NM_MOUNTED=true
	else NM_MOUNTED=false
	fi
	if NetworkMap_Daemon_Running
	then NM_DAEMON=true
	else NM_DAEMON=false
	fi

	echo "enabled=$NM_ENABLED"
	echo "js_source=$([ -s "$NETWORKMAP_SOURCE_JS" ] && echo 'present' || echo 'missing')"
	echo "mounted=$NM_MOUNTED"
	echo "daemon=$NM_DAEMON"
	echo "json=$NETWORKMAP_JSON"
	[ -s "$NETWORKMAP_JSON" ] && cat "$NETWORKMAP_JSON"
}

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
Download_File()
{
   if [ $# -lt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
   then return 1
   fi
   local srcFilePathURL="${1}/$2"
   local tempFilePathDL="${TEMP_DIR}/${2}.DL.$$.TMP"
   local theDestFName="$2"  theDestFPath="$3"
   local logMsgStr  theMsgStr
   local curlRetCode  returnCODE  statusSTRx  httpStatusSTR

   rm -f "$tempFilePathDL"
   printf '' > "$curlErrLogFile"
   printf '' > "$curlTmpLogFile"

   curl -LSs --retry 3 --retry-delay 5 --retry-connrefused \
   --connect-timeout 30 --max-time 60 \
   -w "${curlHTTPstatusStr}: %{http_code}\n" --stderr "$curlErrLogFile" \
   "$srcFilePathURL" --output "$tempFilePathDL" >> "$curlTmpLogFile"
   curlRetCode="$?"

   returnCODE="$curlRetCode"
   statusSTRx="Curl Status Code: $curlRetCode"
   httpStatusSTR="$(grep -oE "${curlHTTPstatusStr}: [4-5][0-9]{2,}" "$curlTmpLogFile")"

   if [ "$curlRetCode" -eq 0 ] && \
      [ -z "$httpStatusSTR" ] && [ -s "$tempFilePathDL" ]
   then
       mv -f "$tempFilePathDL" "$theDestFPath"
       dos2unix "$theDestFPath" ; chmod 644 "$theDestFPath"
   else
       if [ "$curlRetCode" -eq 0 ] && [ -n "$httpStatusSTR" ]
       then
           returnCODE="$(echo "$httpStatusSTR" | awk -F' ' '{print $2}')"
           statusSTRx="HTTP Status Code: $returnCODE"
       fi
       if [ -s "$curlErrLogFile" ] && "$isInteractive"
       then echo ; cat "$curlErrLogFile"
       fi
       logMsgStr="**ERROR**: Unable to download the file [$theDestFName] [${statusSTRx}]"
       theMsgStr="\n${REDct}**ERROR**${CLRct}: Unable to download the file [$theDestFName] [${MGNTct}${statusSTRx}${CLRct}]\n"

       _PrintMsg_ "$theMsgStr"
       Print_Output LogOnly "$logMsgStr" "$ERR"
       rm -f "$tempFilePathDL"
   fi

   rm -f "$curlErrLogFile" "$curlTmpLogFile"
   return "$returnCODE"
}

### function based on @dave14305's FlexQoS webconfigpage function ###
##----------------------------------------##
## Modified by Martinski W. [2025-Mar-16] ##
##----------------------------------------##
Get_WebUI_URL()
{
	local urlPage  urlProto  urlDomain  urlPort  lanPort

	if [ ! -f "$TEMP_MENU_TREE" ]
	then
		echo "**ERROR**: WebUI page NOT mounted"
		return 1
	fi

	urlPage="$(sed -nE "/$SCRIPT_NAME/ s/.*url\: \"(user[0-9]+\.asp)\".*/\1/p" "$TEMP_MENU_TREE")"

	if [ "$(_NVRAM_Get_ http_enable)" -eq 1 ]; then
		urlProto="https"
	else
		urlProto="http"
	fi
	if [ -n "$(_NVRAM_Get_ lan_domain)" ]; then
		urlDomain="$(_NVRAM_Get_ lan_hostname).$(_NVRAM_Get_ lan_domain)"
	else
		urlDomain="$LAN_IPaddr"
	fi

	lanPort="$(_NVRAM_Get_ ${urlProto}_lanport)"
	if [ "$lanPort" -eq 80 ] || [ "$lanPort" -eq 443 ]
	then
		urlPort=""
	else
		urlPort=":$lanPort)"
	fi

	if echo "$urlPage" | grep -qE "^${webPageFileRegExp}$" && \
	   [ -s "${SCRIPT_WEBPAGE_DIR}/$urlPage" ]
	then
		echo "${urlProto}://${urlDomain}${urlPort}/${urlPage}" | tr "A-Z" "a-z"
	else
		echo "**ERROR**: WebUI page NOT found"
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Mar-16] ##
##-------------------------------------##
_Check_WebGUI_Page_Exists_()
{
   local webPageStr  webPageFile  theWebPage

   if [ ! -f "$TEMP_MENU_TREE" ]
   then echo "NONE" ; return 1 ; fi

   theWebPage="NONE"
   webPageStr="$(grep -E -m1 "^$webPageLineRegExp" "$TEMP_MENU_TREE")"
   if [ -n "$webPageStr" ]
   then
       webPageFile="$(echo "$webPageStr" | grep -owE "$webPageFileRegExp" | head -n1)"
       if [ -n "$webPageFile" ] && [ -s "${SCRIPT_WEBPAGE_DIR}/$webPageFile" ]
       then theWebPage="$webPageFile" ; fi
   fi
   echo "$theWebPage"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Mar-16] ##
##----------------------------------------##
Get_WebUI_Page()
{
	local webPageFile  webPagePath

	if [ ! -s "$1" ]
	then MyWebPage="NONE" ; return 1
	fi
	MyWebPage="$(_Check_WebGUI_Page_Exists_)"

	for indx in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20
	do
		webPageFile="user${indx}.asp"
		webPagePath="${SCRIPT_WEBPAGE_DIR}/$webPageFile"

		if [ -s "$webPagePath" ] && \
		   [ "$(md5sum < "$1")" = "$(md5sum < "$webPagePath")" ]
		then
			MyWebPage="$webPageFile"
			break
		elif [ "$MyWebPage" = "NONE" ] && [ ! -s "$webPagePath" ]
		then
			MyWebPage="$webPageFile"
		fi
	done
}

### locking mechanism code credit to Martineau (@MartineauUK) ###
##----------------------------------------##
## Modified by Martinski W. [2025-Mar-16] ##
##----------------------------------------##
Mount_WebUI()
{
	Print_Output true "Mounting WebUI tab for $SCRIPT_NAME" "$PASS"
	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"
	Get_WebUI_Page "$SCRIPT_DIR/YazFi_www.asp"
	if [ "$MyWebPage" = "NONE" ]
	then
		Print_Output true "**ERROR** Unable to mount $SCRIPT_NAME WebUI page, exiting" "$CRIT"
		flock -u "$FD"
		return 1
	fi
	cp -fp "$SCRIPT_DIR/YazFi_www.asp" "$SCRIPT_WEBPAGE_DIR/$MyWebPage"
	echo "$SCRIPT_NAME" > "$SCRIPT_WEBPAGE_DIR/$(echo "$MyWebPage" | cut -f1 -d'.').title"

	if [ "$(/bin/uname -o)" = "ASUSWRT-Merlin" ]
	then
		if [ ! -f "$TEMP_MENU_TREE" ]; then
			cp -fp /www/require/modules/menuTree.js "$TEMP_MENU_TREE"
		fi

		sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"

		sed -i "/url: \"Guest_network.asp\", tabName:/a {url: \"$MyWebPage\", tabName: \"$SCRIPT_NAME\"}," "$TEMP_MENU_TREE"

		umount /www/require/modules/menuTree.js 2>/dev/null
		mount -o bind "$TEMP_MENU_TREE" /www/require/modules/menuTree.js
	fi
	flock -u "$FD"
	Print_Output true "Mounted $SCRIPT_NAME WebUI page as $MyWebPage" "$PASS"
}

##-------------------------------------##
## Added by Martinski W. [2025-Mar-16] ##
##-------------------------------------##
_CheckFor_WebGUI_Page_()
{
   if [ "$(_Check_WebGUI_Page_Exists_)" = "NONE" ]
   then Mount_WebUI ; fi
}

##-------------------------------------##
_CheckFor_NetworkMap_SourceJS_()
{
	if [ ! -s "$NETWORKMAP_SOURCE_JS" ]
	then
		Print_Output true "Network Map JS source missing - attempting repair" "$WARN"
		Update_File YazFi_networkmap.js
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
Config_Download()
{
	mkdir -p "$SCRIPT_DIR"
	Download_File "$SCRIPT_REPO" "${SCRIPT_NAME}.config.example" "$1"
	sleep 1
	Clear_Lock
	[ -s "$1" ] && return 0 || return 1
}

##-------------------------------------##
## Added by Martinski W. [2022-Dec-26] ##
##-------------------------------------##
Config_ADD_Download()
{
	config_ADD="${1}.ADD.txt"
	Download_File "$SCRIPT_REPO" "${SCRIPT_NAME}.config.ADD.txt" "$config_ADD"
	[ -s "$config_ADD" ] && return 0 || return 1
}

##----------------------------------------##
## Modified by Martinski W. [2026-Aug-20] ##
##----------------------------------------##
Conf_Exists()
{
	if [ -s "$SCRIPT_CONF" ]
	then
		chmod 644 "$SCRIPT_CONF"
		_DOStoUNIX_ "$SCRIPT_CONF"
		Update_File "$SCRIPT_CONF"

		if [ ! -s "${SCRIPT_CONF}.bak" ]
		then
			cp -fp "$SCRIPT_CONF" "${SCRIPT_CONF}.bak"
		fi
		if grep -q '_LANACCESS=' "$SCRIPT_CONF"
		then
			sed -i -e 's/_LANACCESS=/_TWOWAYTOGUEST=/g' "$SCRIPT_CONF"
		fi
		if ! grep -q "_ONEWAYTOGUEST=" "$SCRIPT_CONF"
		then
			for CONFIFACE in $IFACELIST_FULL
			do
				CONFIFACETMP="$(Get_Iface_Var "$CONFIFACE")"
				sed -i "/^${CONFIFACETMP}_TWOWAYTOGUEST=/a ${CONFIFACETMP}_ONEWAYTOGUEST=false" "$SCRIPT_CONF"
			done
		fi
		if ! grep -q "_ALLOWINTERNET=" "$SCRIPT_CONF"
		then
			for CONFIFACE in $IFACELIST_FULL
			do
				CONFIFACETMP="$(Get_Iface_Var "$CONFIFACE")"
				sed -i "/^${CONFIFACETMP}_FORCEDNS=/a ${CONFIFACETMP}_ALLOWINTERNET=true" "$SCRIPT_CONF"
			done
		fi
		if ! grep -q "_ONEWAYTOGUEST_MODE=" "$SCRIPT_CONF"
		then
			for IFaceID in $IFACELIST_FULL
			do
				IFaceVar="$(Get_Iface_Var "$IFaceID")"
				sed -i "/^${IFaceVar}_CLIENTISOLATION=/a ${IFaceVar}_ONEWAYTOGUEST_MODE=NAT" "$SCRIPT_CONF"
			done
		fi
		if ! grep -q "_TWOWAYTOGUEST_MODE=" "$SCRIPT_CONF"
		then
			for IFaceID in $IFACELIST_FULL
			do
				IFaceVar="$(Get_Iface_Var "$IFaceID")"
				sed -i "/^${IFaceVar}_CLIENTISOLATION=/a ${IFaceVar}_TWOWAYTOGUEST_MODE=NAT" "$SCRIPT_CONF"
			done
		fi

		sed -i -e 's/"//g' "$SCRIPT_CONF"
		. "$SCRIPT_CONF"
		return 0
	else
		return 1
	fi
}

Firewall_Chains()
{
	FWRDSTART="$(iptables -nvL FORWARD --line | grep -E "all.*state RELATED,ESTABLISHED" | tail -1 | awk '{print $1}')"

	case $1 in
		create)
			for CHAIN in $CHAINS
			do
				if ! iptables -n -L "$CHAIN" >/dev/null 2>&1
				then
					iptables -N "$CHAIN"
					case $CHAIN in
						"$INPT")
							iptables -I INPUT -j "$CHAIN"
						;;
						"$FWRD")
							iptables -I FORWARD "$FWRDSTART" -j "$CHAIN"
						;;
						"$LGRJT")
							iptables -I "$LGRJT" -j REJECT

							if [ -f "$SCRIPT_DIR/.rejectlogging" ]; then
								iptables -I $LGRJT -j LOG --log-prefix "REJECT " --log-tcp-sequence --log-tcp-options --log-ip-options
							fi
						;;
						"$DNSFLTR_DOT")
							iptables -I FORWARD "$FWRDSTART" -p tcp -m tcp --dport 853 -j "$CHAIN"
						;;
					esac
				fi
			done
			for CHAIN in $NATCHAINS
			do
				if ! iptables -t nat -n -L "$CHAIN" >/dev/null 2>&1
				then
					iptables -t nat -N "$CHAIN"
					case $CHAIN in
						"$DNSFLTR")
							### DNSFilter rules - credit to @RMerlin for the original implementation in Asuswrt ###
							iptables -t nat -I PREROUTING -p udp -m udp --dport 53 -j "$CHAIN"
							iptables -t nat -I PREROUTING -p tcp -m tcp --dport 53 -j "$CHAIN"
							###
						;;
					esac
				fi
			done
		;;
		deleteall)
			for CHAIN in $CHAINS
			do
				if iptables -n -L "$CHAIN" >/dev/null 2>&1
				then
					case $CHAIN in
						"$INPT")
							iptables -D INPUT -j "$CHAIN"
						;;
						"$FWRD")
							iptables -D FORWARD -j "$CHAIN"
						;;
						"$LGRJT")
							iptables -D "$LGRJT" -j REJECT
						;;
						"$DNSFLTR_DOT")
							iptables -D FORWARD -p tcp -m tcp --dport 853 -j "$CHAIN"
						;;
					esac

					iptables -F "$CHAIN"
					iptables -X "$CHAIN"
				fi
			done
			for CHAIN in $NATCHAINS
			do
				if ! iptables -t nat -n -L "$CHAIN" >/dev/null 2>&1
				then
					case $CHAIN in
						"$DNSFLTR")
							iptables -t nat -D PREROUTING -p udp -m udp --dport 53 -j "$CHAIN"
							iptables -t nat -D PREROUTING -p tcp -m tcp --dport 53 -j "$CHAIN"
						;;
					esac

					iptables -F "$CHAIN"
					iptables -X "$CHAIN"
				fi
			done
		;;
	esac
}

##-------------------------------------##
## Added by Martinski W. [2023-Dec-28] ##
##-------------------------------------##
_GetNetworkIPaddrCIDR_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 1 ; fi
   local netIPinfo  netIPaddr
   netIPinfo="$(ip route show | grep "dev[[:blank:]]* ${1}[[:blank:]]* proto kernel")"
   [ -z "$netIPinfo" ] && echo "" && return 1
   netIPaddr="$(echo "$netIPinfo" | awk -F ' ' '{print $1}')"
   echo "$netIPaddr" ; return 0
}

##-------------------------------------##
## Added by Martinski W. [2023-Dec-22] ##
##-------------------------------------##
Firewall_Rules_ONEorTWO_WAY()
{
	ACTIONS=""
	IFACE="$2"

	GuestNetBandID="$(Get_Guest_Name "$IFACE")"
	doClientIsolation="$(eval echo '$'"$(Get_Iface_Var "$IFACE")_CLIENTISOLATION")"
	doTWO_WAYtoGUEST="$(eval echo '$'"$(Get_Iface_Var "$IFACE")_TWOWAYTOGUEST")"
	doONE_WAYtoGUEST="$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ONEWAYTOGUEST")"

	case $1 in
		delete) ACTIONS="-D" ;;
		create) ACTIONS="-D -I" ;;
	esac

	for ACTION in $ACTIONS
	do
		if [ "$doTWO_WAYtoGUEST" = "true" ]
		then
			iptables "$ACTION" "$FWRD" -i "$IFACE" -o "$LAN_IFname" -m comment --comment "$GuestNetBandID to LAN" -j ACCEPT
		fi
		if [ "$doONE_WAYtoGUEST" = "true" ]
		then
			iptables "$ACTION" "$FWRD" -i "$IFACE" -o "$LAN_IFname" -m state --state RELATED,ESTABLISHED -j ACCEPT
		fi
		if [ "$doONE_WAYtoGUEST" = "true" ] || [ "$doTWO_WAYtoGUEST" = "true" ]
		then
			iptables "$ACTION" "$FWRD" -i "$LAN_IFname" -o "$IFACE" -m comment --comment "LAN to $GuestNetBandID" -j ACCEPT
			if [ "$doClientIsolation" = "true" ]
			then
			    iptables "$ACTION" "$FWRD" -i wl+ -o "$IFACE" -j "$LGRJT"
			    iptables "$ACTION" "$FWRD" -i "$IFACE" -o wl+ -j "$LGRJT"
			fi
		fi
	done
}

##----------------------------------------##
## Modified by Martinski W. [2026-Aug-20] ##
##----------------------------------------##
Firewall_Rules()
{
	ACTIONS=""
	IFACE="$2"

	LAN_IPcidr="$(_GetNetworkIPaddrCIDR_ "$LAN_IFname")"
	[ -z "$LAN_IPcidr" ] && LAN_IPcidr="${LAN_IPaddr%.*}.0/24"

	GuestNetBandID="$(Get_Guest_Name "$IFACE")"
	GuestNetIPaddr="$(eval echo '$'"$(Get_Iface_Var "$IFACE")_IPADDR" | cut -f1-3 -d".")"
	GuestNetIPcidr="${GuestNetIPaddr}.0/24"
	doTWO_WAYtoGUEST="$(eval echo '$'"$(Get_Iface_Var "$IFACE")_TWOWAYTOGUEST")"
	doONE_WAYtoGUEST="$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ONEWAYTOGUEST")"
	TwoWayToGuestMODE="$(_TwoWayToGuest_RoutingType_ check "$IFACE")"
	OneWayToGuestMODE="$(_OneWayToGuest_RoutingType_ check "$IFACE")"

	case $1 in
		delete) ACTIONS="-D" ;;
		create) ACTIONS="-D -I" ;;
	esac

	for ACTION in $ACTIONS
	do
		ebtables -t broute "$ACTION" BROUTING -p ipv4 -i "$IFACE" -j DROP
		ebtables -t broute "$ACTION" BROUTING -p ipv6 -i "$IFACE" -j DROP
		ebtables -t broute "$ACTION" BROUTING -p arp -i "$IFACE" -j DROP

		ebtables -t broute -D BROUTING -p IPv4 -i "$IFACE" --ip-dst "$LAN_IPaddr"/24 --ip-proto tcp -j DROP
		ebtables -t broute -D BROUTING -p IPv4 -i "$IFACE" --ip-dst "$LAN_IPaddr" --ip-proto icmp -j ACCEPT
		ebtables -t broute -D BROUTING -p IPv4 -i "$IFACE" --ip-dst "$LAN_IPaddr"/24 --ip-proto icmp -j DROP

		iptables "$ACTION" "$FWRD" -i "$IFACE" -m comment --comment "$GuestNetBandID" -j ACCEPT

		if [ "$doTWO_WAYtoGUEST" = "false" ] || [ "$doONE_WAYtoGUEST" = "false" ]
		then
			iptables -D "$FWRD" -i wl+ -o "$IFACE" -j "$LGRJT"
			iptables -D "$FWRD" -i "$IFACE" -o wl+ -j "$LGRJT"
			iptables -D "$FWRD" ! -i "$IFACE_WAN" -o "$IFACE" -m comment --comment "LAN to $GuestNetBandID" -j ACCEPT
			iptables -D "$FWRD" -i "$LAN_IFname" -o "$IFACE" -m comment --comment "LAN to $GuestNetBandID" -j ACCEPT
			iptables -D "$FWRD" -i "$IFACE" ! -o "$IFACE_WAN" -m comment --comment "$GuestNetBandID to LAN" -j ACCEPT
			iptables -D "$FWRD" -i "$IFACE" -o "$LAN_IFname" -m comment --comment "$GuestNetBandID to LAN" -j ACCEPT
			iptables -D "$FWRD" -i "$IFACE" ! -o "$IFACE_WAN" -m state --state RELATED,ESTABLISHED -j ACCEPT
			iptables -D "$FWRD" -i "$IFACE" -o "$LAN_IFname" -m state --state RELATED,ESTABLISHED -j ACCEPT

			iptables -t nat -D POSTROUTING -s "$LAN_IPcidr" -d "$GuestNetIPcidr" -o "$IFACE" -m comment --comment "LAN to $GuestNetBandID" -j MASQUERADE
			iptables -t nat -D POSTROUTING -s "$GuestNetIPcidr" -d "$LAN_IPcidr" -o "$LAN_IFname" -m comment --comment "$GuestNetBandID to LAN" -j MASQUERADE

			iptables "$ACTION" "$FWRD" -i "$IFACE" ! -o "$IFACE_WAN" -j "$LGRJT"
			iptables "$ACTION" "$FWRD" ! -i "$IFACE_WAN" -o "$IFACE" -j "$LGRJT"
		fi

		if [ "$doTWO_WAYtoGUEST" = "true" ] || [ "$doONE_WAYtoGUEST" = "true" ]
		then
			iptables -D "$FWRD" ! -i "$IFACE_WAN" -o "$IFACE" -j "$LGRJT"

			if [ "$ACTION" = "-D" ] || \
			   { [ "$doTWO_WAYtoGUEST" = "true" ] && [ "$TwoWayToGuestMODE" = "NAT" ] ; } || \
			   { [ "$doONE_WAYtoGUEST" = "true" ] && [ "$OneWayToGuestMODE" = "NAT" ] ; }
			then
				iptables -t nat "$ACTION" POSTROUTING -s "$LAN_IPcidr" -d "$GuestNetIPcidr" -o "$IFACE" -m comment --comment "LAN to $GuestNetBandID" -j MASQUERADE
			fi
		fi

		if [ "$doTWO_WAYtoGUEST" = "true" ]
		then
			iptables -D "$FWRD" -i "$IFACE" ! -o "$IFACE_WAN" -j "$LGRJT"
			iptables "$ACTION" "$FWRD" ! -i "$IFACE_WAN" -o "$IFACE" -m comment --comment "LAN to $GuestNetBandID" -j ACCEPT
			iptables "$ACTION" "$FWRD" -i "$IFACE" ! -o "$IFACE_WAN" -m comment --comment "$GuestNetBandID to LAN" -j ACCEPT

			if [ "$ACTION" = "-D" ] || [ "$TwoWayToGuestMODE" = "NAT" ]
			then
				iptables -t nat "$ACTION" POSTROUTING -s "$GuestNetIPcidr" -d "$LAN_IPcidr" -o "$LAN_IFname" -m comment --comment "$GuestNetBandID to LAN" -j MASQUERADE
			fi
		fi

		if [ "$doONE_WAYtoGUEST" = "true" ]
		then
			iptables "$ACTION" "$FWRD" -i "$IFACE" ! -o "$IFACE_WAN" -m state --state RELATED,ESTABLISHED -j ACCEPT
			iptables "$ACTION" "$FWRD" ! -i "$IFACE_WAN" -o "$IFACE" -m comment --comment "LAN to $GuestNetBandID" -j ACCEPT
		fi

		iptables "$ACTION" "$INPT" -i "$IFACE" -j "$LGRJT"
		iptables "$ACTION" "$INPT" -i "$IFACE" -p icmp -j ACCEPT
		iptables "$ACTION" "$INPT" -i "$IFACE" -p udp -m multiport --dports 67,123 -j ACCEPT

		ENABLED_WINS="$(_NVRAM_Get_ smbd_wins)"
		ENABLED_SAMBA="$(_NVRAM_Get_ enable_samba)"
		if ! Validate_Number "" "$ENABLED_SAMBA" silent; then ENABLED_SAMBA=0; fi
		if ! Validate_Number "" "$ENABLED_WINS" silent; then ENABLED_WINS=0; fi

		if [ "$ENABLED_WINS" -eq 1 ] && [ "$ENABLED_SAMBA" -eq 1 ]; then
			iptables "$ACTION" "$INPT" -i "$IFACE" -p udp -m multiport --dports 137,138 -j ACCEPT
		else
			iptables -D "$INPT" -i "$IFACE" -p udp -m multiport --dports 137,138 -j ACCEPT
		fi

		##----------------------------------------##
		## Modified by Martinski W. [2023-Dec-22] ##
		##----------------------------------------##
		if [ "$doTWO_WAYtoGUEST" = "true" ] || [ "$doONE_WAYtoGUEST" = "true" ]
		then
			iptables "$ACTION" "$INPT" -i "$IFACE" -d 224.0.0.0/4 -j ACCEPT
		else
			iptables -D "$INPT" -i "$IFACE" -d 224.0.0.0/4 -j ACCEPT
		fi

		iptables -t nat -D POSTROUTING -s "$GuestNetIPcidr" -d "$GuestNetIPcidr" -o "$IFACE" -m comment --comment "$(Get_Guest_Name_Old "$IFACE")" -j MASQUERADE
		iptables -t nat "$ACTION" POSTROUTING -s "$GuestNetIPcidr" -d "$GuestNetIPcidr" -o "$IFACE" -m comment --comment "$GuestNetBandID" -j MASQUERADE

		ENABLED_NTPD=0
		if [ -s /jffs/scripts/nat-start ]
		then
			if [ "$(grep -c '# ntpMerlin' /jffs/scripts/nat-start)" -gt 0 ]
			then ENABLED_NTPD=1; fi
		fi

		if [ "$ENABLED_NTPD" -eq 1 ]
		then
			iptables -t nat "$ACTION" PREROUTING -i "$IFACE" -p udp --dport 123 -j DNAT --to "$GuestNetIPaddr"."$(echo "$LAN_IPaddr" | cut -f4 -d'.')"
			iptables -t nat "$ACTION" PREROUTING -i "$IFACE" -p tcp --dport 123 -j DNAT --to "$GuestNetIPaddr"."$(echo "$LAN_IPaddr" | cut -f4 -d'.')"
			iptables "$ACTION" "$FWRD" -i "$IFACE" -p tcp --dport 123 -j REJECT
			iptables "$ACTION" "$FWRD" -i "$IFACE" -p udp --dport 123 -j REJECT
			ip6tables "$ACTION" FORWARD -i "$IFACE" -p tcp --dport 123 -j REJECT
			ip6tables "$ACTION" FORWARD -i "$IFACE" -p udp --dport 123 -j REJECT
		else
			iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport 123 -j DNAT --to "$GuestNetIPaddr"."$(echo "$LAN_IPaddr" | cut -f4 -d'.')"
			iptables -t nat -D PREROUTING -i "$IFACE" -p tcp --dport 123 -j DNAT --to "$GuestNetIPaddr"."$(echo "$LAN_IPaddr" | cut -f4 -d'.')"
			iptables -D "$FWRD" -i "$IFACE" -p tcp --dport 123 -j REJECT
			iptables -D "$FWRD" -i "$IFACE" -p udp --dport 123 -j REJECT
			ip6tables -D FORWARD -i "$IFACE" -p tcp --dport 123 -j REJECT
			ip6tables -D FORWARD -i "$IFACE" -p udp --dport 123 -j REJECT
		fi
	done
}

##----------------------------------------##
## Modified by Martinski W. [2023-Dec-22] ##
##----------------------------------------##
Firewall_BlockInternet()
{
	ACTIONS=""
	IFACE="$2"

	case $1 in
		delete) ACTIONS="-D" ;;
		create) ACTIONS="-D -I" ;;
	esac

	for ACTION in $ACTIONS
	do
		iptables "$ACTION" "$FWRD" -i "$IFACE" -o "$IFACE_WAN" -m comment --comment "$(Get_Guest_Name "$IFACE") block internet" -j "$LGRJT"
		iptables "$ACTION" "$FWRD" -i "$IFACE" -o tun1+ -m comment --comment "$(Get_Guest_Name "$IFACE") block internet" -j "$LGRJT"
		iptables "$ACTION" "$FWRD" -i "$IFACE_WAN" -o "$IFACE" -m comment --comment "$(Get_Guest_Name "$IFACE") block internet" -j DROP
		iptables "$ACTION" "$FWRD" -i tun1+ -o "$IFACE" -m comment --comment "$(Get_Guest_Name "$IFACE") block internet" -j DROP
	done
}

Firewall_DNS()
{
	ACTIONS=""
	IFACE="$2"

	case $1 in
		create)
			ACTIONS="-D -I"
		;;
		delete)
			ACTIONS="-D"
		;;
	esac

	for ACTION in $ACTIONS
	do
		if IP_Local "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" || IP_Local "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS2")"
		then
			RULES=$(iptables -nvL "$INPT" --line-number | grep "$IFACE" | grep "pt:53" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -D "$INPT" "$RULENO"
			done

			RULES=$(iptables -nvL "$FWRD" --line-number | grep "$IFACE" | grep "pt:53" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -D "$FWRD" "$RULENO"
			done

			if IP_Router "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" "$IFACE" || IP_Router "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS2")" "$IFACE"
			then
				if ifconfig "br0:pixelserv-tls" | grep -q "inet addr:" >/dev/null 2>&1
				then
					IP_PXLSRV=$(ifconfig br0:pixelserv-tls | grep "inet addr:" | cut -d: -f2 | awk '{print $1}')
					iptables "$ACTION" "$INPT" -i "$IFACE" -d "$IP_PXLSRV" -p tcp -m multiport --dports 80,443 -j ACCEPT
				else
					RULES=$(iptables -nvL "$INPT" --line-number | grep "$IFACE" | grep "multiport dports 80,443" | awk '{print $1}' | sort -nr)
					for RULENO in $RULES; do
						iptables -D "$INPT" "$RULENO"
					done
				fi

				for PROTO in tcp udp; do
					iptables "$ACTION" "$INPT" -i "$IFACE" -p "$PROTO" --dport 53 -j ACCEPT
				done
			fi
			if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" != "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS2")" ]
			then
				if IP_Local "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" && ! IP_Router "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" "$IFACE"
				then
					for PROTO in tcp udp
					do
						iptables "$ACTION" "$FWRD" -i "$IFACE" -d "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" -p "$PROTO" --dport 53 -j ACCEPT
						iptables "$ACTION" "$FWRD" -o "$IFACE" -s "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" -p "$PROTO" --sport 53 -j ACCEPT
					done
				fi
				if IP_Local "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS2")" && ! IP_Router "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS2")" "$IFACE"
				then
					for PROTO in tcp udp
					do
						iptables "$ACTION" "$FWRD" -i "$IFACE" -d "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS2")" -p "$PROTO" --dport 53 -j ACCEPT
						iptables "$ACTION" "$FWRD" -o "$IFACE" -s "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS2")" -p "$PROTO" --sport 53 -j ACCEPT
					done
				fi
			else
				if ! IP_Router "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" "$IFACE"
				then
					for PROTO in tcp udp
					do
						iptables "$ACTION" "$FWRD" -i "$IFACE" -d "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" -p "$PROTO" --dport 53 -j ACCEPT
						iptables "$ACTION" "$FWRD" -o "$IFACE" -s "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" -p "$PROTO" --sport 53 -j ACCEPT
					done
				fi
			fi
		else
			RULES=$(iptables -nvL "$INPT" --line-number | grep "$IFACE" | grep "pt:53" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -D "$INPT" "$RULENO"
			done

			RULES=$(iptables -nvL "$FWRD" --line-number | grep "$IFACE" | grep "pt:53" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -D "$FWRD" "$RULENO"
			done
		fi

		### DNSFilter rules - credit to @RMerlin for the original implementation in Asuswrt ###
		if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_FORCEDNS")" = "true" ]
		then
			RULES=$(iptables -t nat -nvL "$DNSFLTR" --line-number | grep "$IFACE" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -t nat -D "$DNSFLTR" "$RULENO"
			done

			RULES=$(iptables -nvL $DNSFLTR_DOT --line-number | grep "$IFACE" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -t nat -D "$DNSFLTR_DOT" "$RULENO"
			done

			iptables -t nat "$ACTION" "$DNSFLTR" -i "$IFACE" -j DNAT --to-destination "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")"
			iptables "$ACTION" "$DNSFLTR_DOT" -i "$IFACE" ! -d "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_DNS1")" -j "$LGRJT"
		else
			RULES=$(iptables -t nat -nvL "$DNSFLTR" --line-number | grep "$IFACE" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -t nat -D "$DNSFLTR" "$RULENO"
			done

			RULES=$(iptables -nvL $DNSFLTR_DOT --line-number | grep "$IFACE" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -t nat -D "$DNSFLTR_DOT" "$RULENO"
			done
		fi
		###
	done
}

##----------------------------------------##
## Modified by Martinski W. [2023-Dec-28] ##
##----------------------------------------##
Firewall_NVRAM()
{
	case $1 in
		enable)
			nvram set "${2}"_ap_isolate=1
		;;
		disable)
			nvram set "${2}"_ap_isolate=0
		;;
		disableall)
			for IFACE in $IFACELIST; do
				Firewall_NVRAM disable "$IFACE" 2>/dev/null
			done
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2023-Dec-22] ##
##----------------------------------------##
Firewall_NAT()
{
	case $1 in
		create)
			for ACTION in -D -I
			do
				iptables -t nat -D POSTROUTING -s "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".")".0/24 -o tun1"$3" -m comment --comment "$(Get_Guest_Name_Old "$2") VPN" -j MASQUERADE
				iptables -t nat "$ACTION" POSTROUTING -s "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".")".0/24 -o tun1"$3" -m comment --comment "$(Get_Guest_Name "$2") VPN" -j MASQUERADE
				iptables "$ACTION" "$FWRD" -i "$2" -o "$IFACE_WAN" -j "$LGRJT"
				iptables "$ACTION" "$FWRD" -i "$IFACE_WAN" -o "$2" -j "$LGRJT"
				iptables "$ACTION" "$FWRD" -i "$2" -o tun1"$3" -j ACCEPT
				iptables "$ACTION" "$FWRD" -i tun1"$3" -o "$2" -j ACCEPT
			done
		;;
		delete)
			RULES=$(iptables -t nat -nvL POSTROUTING --line-number | grep "$(Get_Guest_Name_Old "$2") VPN" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -t nat -D POSTROUTING "$RULENO"
			done

			RULES=$(iptables -t nat -nvL POSTROUTING --line-number | grep "$(Get_Guest_Name "$2") VPN" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -t nat -D POSTROUTING "$RULENO"
			done

			RULES=$(iptables -nvL "$FWRD" --line-number | grep "$2" | grep "tun1" | awk '{print $1}' | sort -nr)
			for RULENO in $RULES; do
				iptables -D "$FWRD" "$RULENO"
			done

			iptables -D "$FWRD" -i "$2" -o "$IFACE_WAN" -j "$LGRJT"
			iptables -D "$FWRD" -i "$IFACE_WAN" -o "$2" -j "$LGRJT"
		;;
		deleteall)
			for IFACE in $IFACELIST; do
				Firewall_NAT delete "$IFACE" 2>/dev/null
			done
		;;
	esac
}

Routing_RPDB()
{
	case $1 in
		create)
			if ! ip route show | grep -q "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR")"
			then
				ip route del "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".")".0/24 dev "$2" proto kernel src "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")"
				ip route add "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".")".0/24 dev "$2" proto kernel src "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")"
			fi
			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				if ifconfig "tun1$COUNTER" >/dev/null 2>&1
				then
					if ! ip route show table ovpnc"$COUNTER" | grep -q "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR")"
					then
						ip route del "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".")".0/24 dev "$2" proto kernel table ovpnc"$COUNTER" src "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")"
						ip route add "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".")".0/24 dev "$2" proto kernel table ovpnc"$COUNTER" src "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")"
					fi
				fi
				COUNTER="$((COUNTER+1))"
			done
		;;
		delete)
			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				if ifconfig "tun1$COUNTER" >/dev/null 2>&1
				then
					ip route del "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".")".0/24 dev "$2" proto kernel table ovpnc"$COUNTER" src "$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")"
				fi
				COUNTER="$((COUNTER+1))"
			done
		;;
	esac

	ip route flush cache
}

Routing_VPNDirector()
{
	case $1 in
		initialise)
			VPN_IP_LIST_ORIG=$(cat /jffs/openvpn/vpndirector_rulelist)
			VPN_IP_LIST_NEW="$VPN_IP_LIST_ORIG"
		;;
		create)
			VPN_IFACE_NVRAM=""
			VPN_IFACE_NVRAM="<1>$(Get_Guest_Name "$2")>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>>OVPN$3"

			if ! echo "$VPN_IP_LIST_ORIG" | grep -q "$VPN_IFACE_NVRAM"
			then
				Routing_VPNDirector delete "$2"
				VPN_IP_LIST_NEW="${VPN_IP_LIST_NEW}${VPN_IFACE_NVRAM}"
			fi

			VPN_IFACE_NVRAM_SAFE="$(echo "<0>$(Get_Guest_Name "$2")>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>>OVPN$3" | sed -e 's/\//\\\//g;s/\./\\./g;s/ /\\ /g')"
			VPN_IP_LIST_NEW=$(echo "$VPN_IP_LIST_NEW" | sed -e "s/$VPN_IFACE_NVRAM_SAFE//g")

			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				if [ "$COUNTER" -eq "$3" ]
				then
					COUNTER="$((COUNTER + 1))"
					continue
				fi
				VPN_IFACE_NVRAM_SAFE="$(echo "<0>$(Get_Guest_Name "$2")>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>>OVPN$COUNTER" | sed -e 's/\//\\\//g;s/\./\\./g;s/ /\\ /g')"
				VPN_IP_LIST_NEW=$(echo "$VPN_IP_LIST_NEW" | sed -e "s/$VPN_IFACE_NVRAM_SAFE//g")
				VPN_IFACE_NVRAM_SAFE="$(echo "<1>$(Get_Guest_Name "$2")>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>>OVPN$COUNTER" | sed -e 's/\//\\\//g;s/\./\\./g;s/ /\\ /g')"
				VPN_IP_LIST_NEW=$(echo "$VPN_IP_LIST_NEW" | sed -e "s/$VPN_IFACE_NVRAM_SAFE//g")
				COUNTER="$((COUNTER + 1))"
			done
		;;
		delete)
			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				VPN_IP_LIST_NEW=$(echo "$VPN_IP_LIST_NEW" | sed -e "s/$(echo '<0>'"$(Get_Guest_Name "$2")" | sed -e 's/\//\\\//g;s/ /\\ /g')>[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\/24>>OVPN$COUNTER//g")
				VPN_IP_LIST_NEW=$(echo "$VPN_IP_LIST_NEW" | sed -e "s/$(echo '<1>'"$(Get_Guest_Name "$2")" | sed -e 's/\//\\\//g;s/ /\\ /g')>[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\/24>>OVPN$COUNTER//g")
				COUNTER="$((COUNTER + 1))"
			done
		;;
		deleteall)
			Routing_VPNDirector initialise 2>/dev/null

			for IFACE in $IFACELIST; do
				Routing_VPNDirector delete "$IFACE" 2>/dev/null
			done

			Routing_VPNDirector save 2>/dev/null
		;;
		save)
			if [ "$VPN_IP_LIST_ORIG" != "$VPN_IP_LIST_NEW" ]
			then
				printf "%s" "$VPN_IP_LIST_NEW" > /jffs/openvpn/vpndirector_rulelist

				COUNTER=1
				until [ "$COUNTER" -gt 5 ]
				do
					if ifconfig "tun1$COUNTER" >/dev/null 2>&1
					then
						if [ "$(_NVRAM_Get_ vpn_client"$COUNTER"_rgw)" -ne 2 ]
						then
							nvram set vpn_client"$COUNTER"_rgw=2
							nvram commit
						fi
					fi
					COUNTER="$((COUNTER + 1))"
				done

				service restart_vpnrouting0 >/dev/null 2>&1
			fi
		;;
	esac
}

Routing_NVRAM()
{
	case $1 in
		initialise)
			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				eval "VPN_IP_LIST_ORIG_$COUNTER=$(echo "$(_NVRAM_Get_ "vpn_client${COUNTER}_clientlist")$(_NVRAM_Get_ "vpn_client${COUNTER}_clientlist1")$(_NVRAM_Get_ "vpn_client${COUNTER}_clientlist2")$(_NVRAM_Get_ "vpn_client${COUNTER}_clientlist3")$(_NVRAM_Get_ "vpn_client${COUNTER}_clientlist4")$(_NVRAM_Get_ "vpn_client${COUNTER}_clientlist5")" | Escape_Sed)"
				eval "VPN_IP_LIST_NEW_$COUNTER=$(eval echo '$'"VPN_IP_LIST_ORIG_"$COUNTER | Escape_Sed)"
				COUNTER="$((COUNTER + 1))"
			done
		;;
		create)
			VPN_NVRAM="$(Get_Guest_Name "$2")"
			VPN_IFACE_NVRAM=""
			if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.384.18)" ]
			then
				VPN_IFACE_NVRAM="<$VPN_NVRAM>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>0.0.0.0>VPN"
			else
				VPN_IFACE_NVRAM="<$VPN_NVRAM>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>>VPN"
			fi
			VPN_IFACE_NVRAM_SAFE="$(echo "$VPN_IFACE_NVRAM" | sed -e 's/\//\\\//g;s/\./\\./g;s/ /\\ /g')"

			if ! eval echo '$'"VPN_IP_LIST_ORIG_$3" | grep -q "$VPN_IFACE_NVRAM"; then
				Routing_NVRAM delete "$2"
				eval "VPN_IP_LIST_NEW_$3=$(echo "$(eval echo '$'"VPN_IP_LIST_NEW_$3")$VPN_IFACE_NVRAM" | Escape_Sed)"
			fi

			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				if [ "$COUNTER" -eq "$3" ]
				then
					COUNTER="$((COUNTER + 1))"
					continue
				fi
				eval "VPN_IP_LIST_NEW_$COUNTER=$(eval echo '$'"VPN_IP_LIST_NEW_$COUNTER" | sed -e "s/$VPN_IFACE_NVRAM_SAFE//g" | Escape_Sed)"
				COUNTER="$((COUNTER + 1))"
			done

			VPN_NVRAM="$(Get_Guest_Name_Old "$2")"
			VPN_IFACE_NVRAM=""
			if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.384.18)" ]
			then
				VPN_IFACE_NVRAM="<$VPN_NVRAM>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>0.0.0.0>VPN"
			else
				VPN_IFACE_NVRAM="<$VPN_NVRAM>$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").0/24>>VPN"
			fi
			VPN_IFACE_NVRAM_SAFE="$(echo "$VPN_IFACE_NVRAM" | sed -e 's/\//\\\//g;s/\./\\./g;s/ /\\ /g')"

			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				eval "VPN_IP_LIST_NEW_$COUNTER=$(eval echo '$'"VPN_IP_LIST_NEW_$COUNTER" | sed -e "s/$VPN_IFACE_NVRAM_SAFE//g" | Escape_Sed)"
				COUNTER="$((COUNTER + 1))"
			done
		;;
		delete)
			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				VPN_NVRAM="$(Get_Guest_Name_Old "$2")"
				eval "VPN_IP_LIST_NEW_$COUNTER=$(echo "$(eval echo '$'"VPN_IP_LIST_NEW_$COUNTER")" | sed -e "s/$(echo '<'$VPN_NVRAM | sed -e 's/\//\\\//g' | sed -e 's/ /\\ /g').*>VPN//g" | Escape_Sed)"
				VPN_NVRAM="$(Get_Guest_Name "$2")"
				eval "VPN_IP_LIST_NEW_$COUNTER=$(echo "$(eval echo '$'"VPN_IP_LIST_NEW_$COUNTER")" | sed -e "s/$(echo '<'$VPN_NVRAM | sed -e 's/\//\\\//g' | sed -e 's/ /\\ /g').*>VPN//g" | Escape_Sed)"
				COUNTER="$((COUNTER + 1))"
			done
		;;
		deleteall)
			Routing_NVRAM initialise 2>/dev/null

			for IFACE in $IFACELIST; do
				Routing_NVRAM delete "$IFACE" 2>/dev/null
			done

			Routing_NVRAM save 2>/dev/null
		;;
		save)
			COUNTER=1
			until [ "$COUNTER" -gt 5 ]
			do
				if [ "$(eval echo '$'"VPN_IP_LIST_ORIG_$COUNTER")" != "$(eval echo '$'"VPN_IP_LIST_NEW_$COUNTER")" ]
				then
					Print_Output true "VPN Client $COUNTER client list has changed, restarting VPN Client $COUNTER" "$PASS"

					if [ "$(/bin/uname -m)" = "aarch64" ]
					then
						fullstring="$(eval echo '$'"VPN_IP_LIST_NEW_"$COUNTER)"
						nvram set vpn_client"$COUNTER"_clientlist="$(echo "$fullstring" | cut -c0-255)"
						nvram set vpn_client"$COUNTER"_clientlist1="$(echo "$fullstring" | cut -c256-510)"
						nvram set vpn_client"$COUNTER"_clientlist2="$(echo "$fullstring" | cut -c511-765)"
						nvram set vpn_client"$COUNTER"_clientlist3="$(echo "$fullstring" | cut -c766-1020)"
						nvram set vpn_client"$COUNTER"_clientlist4="$(echo "$fullstring" | cut -c1021-1275)"
						nvram set vpn_client"$COUNTER"_clientlist5="$(echo "$fullstring" | cut -c1276-1530)"
					else
						nvram set vpn_client"$COUNTER"_clientlist="$(eval echo '$'"VPN_IP_LIST_NEW_$COUNTER")"
					fi

					if [ "$(_NVRAM_Get_ vpn_client"$COUNTER"_rgw)" -ne 2 ]; then
						nvram set vpn_client"$COUNTER"_rgw=2
					fi
					nvram commit
					service restart_vpnclient$COUNTER >/dev/null 2>&1
				fi
				COUNTER="$((COUNTER + 1))"
			done
		;;
	esac
}

DHCP_Conf()
{
	case "$1" in
		initialise)
			if [ -s /jffs/configs/dnsmasq.conf.add ]
			then
				for IFACE in $IFACELIST
				do
					BEGIN="### Start of script-generated configuration for interface $IFACE ###"
					END="### End of script-generated configuration for interface $IFACE ###"
					if grep -q "### Start of script-generated configuration for interface $IFACE ###" /jffs/configs/dnsmasq.conf.add
					then
						sed -i -e '/'"$BEGIN"'/,/'"$END"'/c\' /jffs/configs/dnsmasq.conf.add
					fi
				done
			fi
			if [ -s "$DNSCONF" ]
			then
				cp -fp "$DNSCONF" "$TMPCONF"
			else
				touch "$TMPCONF"
			fi
		;;
		create)
			CONFSTRING=""
			CONFADDSTRING=""

			ENABLED_WINS="$(_NVRAM_Get_ smbd_wins)"
			ENABLED_SAMBA="$(_NVRAM_Get_ enable_samba)"
			if ! Validate_Number "" "$ENABLED_SAMBA" silent; then ENABLED_SAMBA=0; fi
			if ! Validate_Number "" "$ENABLED_WINS" silent; then ENABLED_WINS=0; fi

			ENABLED_NTPD=0
			if [ -f /jffs/scripts/nat-start ]; then
				if [ "$(grep -c '# ntpMerlin' /jffs/scripts/nat-start)" -gt 0 ]; then ENABLED_NTPD=1; fi
			fi

			if [ "$ENABLED_WINS" -eq 1 ] && [ "$ENABLED_SAMBA" -eq 1 ]; then
				CONFADDSTRING="$CONFADDSTRING||||dhcp-option=$2,44,$LAN_IPaddr"
			fi

			if [ "$ENABLED_NTPD" -eq 1 ]; then
				CONFADDSTRING="$CONFADDSTRING||||dhcp-option=$2,42,$LAN_IPaddr"
			fi

			##----------------------------------------------##
			## Added/modified by Martinski W. [2023-Jan-24] ##
			##----------------------------------------------##
			DHCP_LEASE_VAL="$(eval echo '$'"$(Get_Iface_Var "$2")_DHCPLEASE")"
			if ! Validate_DHCP_LeaseTime "$(Get_Iface_Var "$2")_DHCPLEASE" "$DHCP_LEASE_VAL"
			then
				DHCP_LEASE_VAL="$(_NVRAM_Get_ dhcp_lease)"
				if ! Validate_Number "" "$DHCP_LEASE_VAL" silent ; then DHCP_LEASE_VAL=86400 ; fi
			fi
			if [ "$DHCP_LEASE_VAL" = "0" ] || [ "$DHCP_LEASE_VAL" = "$InfiniteLeaseTimeTag" ]
			then DHCP_LEASE_VAL="$InfiniteLeaseTimeVal"
			elif echo "$DHCP_LEASE_VAL" | grep -q "^[0-9]\{1,7\}$"
			then DHCP_LEASE_VAL="${DHCP_LEASE_VAL}s" ; fi

			##----------------------------------------##
			## Modified by Martinski W. [2022-Apr-07] ##
			##----------------------------------------##
			CONFSTRING="interface=$2||||dhcp-range=$2,$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(eval echo '$'"$(Get_Iface_Var "$2")_DHCPSTART"),$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(eval echo '$'"$(Get_Iface_Var "$2")_DHCPEND"),255.255.255.0,${DHCP_LEASE_VAL}||||dhcp-option=$2,3,$(eval echo '$'"$(Get_Iface_Var "$2")_IPADDR" | cut -f1-3 -d".").$(echo "$LAN_IPaddr" | cut -f4 -d".")||||dhcp-option=$2,6,$(eval echo '$'"$(Get_Iface_Var "$2")_DNS1"),$(eval echo '$'"$(Get_Iface_Var "$2")_DNS2")$CONFADDSTRING"

			BEGIN="### Start of script-generated configuration for interface $2 ###"
			END="### End of script-generated configuration for interface $2 ###"
			if grep -q "### Start of script-generated configuration for interface $2 ###" "$TMPCONF"
			then
				sed -i -e '/'"$BEGIN"'/,/'"$END"'/c\'"$BEGIN"'||||'"$CONFSTRING"'||||'"$END" "$TMPCONF"
			else
				printf "\\n%s\\n%s\\n%s\\n" "$BEGIN" "$CONFSTRING" "$END" >> "$TMPCONF"
			fi
		;;
		delete)
			BEGIN="### Start of script-generated configuration for interface $2 ###"
			END="### End of script-generated configuration for interface $2 ###"
			if grep -q "### Start of script-generated configuration for interface $2 ###" "$TMPCONF"
			then
				sed -i -e '/'"$BEGIN"'/,/'"$END"'/c\' "$TMPCONF"
			fi
		;;
		deleteall)
			DHCP_Conf initialise 2>/dev/null
			for IFACE in $IFACELIST
			do
				BEGIN="### Start of script-generated configuration for interface $IFACE ###"
				END="### End of script-generated configuration for interface $IFACE ###"
				if grep -q "### Start of script-generated configuration for interface $IFACE ###" "$TMPCONF"
				then
					sed -i -e '/'"$BEGIN"'/,/'"$END"'/c\' "$TMPCONF"
				fi
			done

			DHCP_Conf save 2>/dev/null
		;;
		save)
			sed -i -e 's/||||/\n/g' "$TMPCONF"

			if ! diff -q "$DNSCONF" "$TMPCONF" >/dev/null 2>&1
			then
				cp "$TMPCONF" "$DNSCONF"
				service restart_dnsmasq >/dev/null 2>&1
				Print_Output true "DHCP configuration updated" "$PASS"
				sleep 2
			fi

			rm -f "$TMPCONF"
		;;
	esac
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-17] ##
##-------------------------------------##
_NVRAM_Get_WAN_IFace_()
{
    local wanPrefix="wan0"  wanProto  WAN_IFace

    wanProto="$(_NVRAM_Get_ "${wanPrefix}_proto")"
    if [ "$wanProto" = "l2tp" ] || \
       [ "$wanProto" = "pptp" ] || \
       [ "$wanProto" = "pppoe" ]
    then
        WAN_IFace="$(_NVRAM_Get_ "${wanPrefix}_pppoe_ifname")"
    else
        WAN_IFace="$(_NVRAM_Get_ "${wanPrefix}_ifname")"
    fi
    echo "$WAN_IFace"
    return 0
}

##------------------------------------------##
## Modified by ExtremeFiretop [2026-Jul-02] ##
##------------------------------------------##
Config_Networks()
{
	Print_Output true "$SCRIPT_NAME $SCRIPT_VERSION starting up" "$PASS"
	WIRELESSRESTART="false"
	GUESTLANENABLED="false"

	Create_Dirs
	Create_Symlinks

	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_DNSMASQ create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Auto_NetworkMapServiceEventEnd create 2>/dev/null
	Auto_ServiceStart create 2>/dev/null
	Auto_OpenVPNEvent create 2>/dev/null

	if ! Conf_Exists
	then
		Config_Download "$SCRIPT_CONF"
		Clear_Lock
		return 1
	fi
	if ! Conf_Validate
	then
		Clear_Lock
		return 1
	fi
	. $SCRIPT_CONF
	modprobe xt_comment

	DHCP_Conf initialise 2>/dev/null

	IFACE_WAN="$(_NVRAM_Get_WAN_IFace_)"

	if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.3)" ]
	then
		Routing_NVRAM initialise 2>/dev/null
	else
		Routing_VPNDirector initialise 2>/dev/null
	fi

	Firewall_Chains create 2>/dev/null
	iptables -F "$DNSFLTR_DOT" 2>/dev/null

	for IFACE in $IFACELIST
	do
		VPNCLIENTNO=$(eval echo '$'"$(Get_Iface_Var "$IFACE")_VPNCLIENTNUMBER")

		if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ENABLED")" = "true" ] && \
		   Validate_IFACE_Enabled "$IFACE" silent
		then
			Iface_Manage create "$IFACE" 2>/dev/null

			Firewall_Rules create "$IFACE" 2>/dev/null

			if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ALLOWINTERNET")" = "true" ]
			then
				if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_REDIRECTALLTOVPN")" = "true" ]
				then
					Print_Output true "$IFACE (SSID: $(_NVRAM_Get_ "${IFACE}_ssid")) - VPN redirection enabled, sending all interface internet traffic over VPN Client $VPNCLIENTNO" "$PASS"

					if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.3)" ]
					then
						Routing_NVRAM create "$IFACE" "$VPNCLIENTNO" 2>/dev/null
					else
						Routing_VPNDirector create "$IFACE" "$VPNCLIENTNO" 2>/dev/null
					fi

					Firewall_NAT create "$IFACE" "$VPNCLIENTNO" 2>/dev/null
				else
					Print_Output true "$IFACE (SSID: $(_NVRAM_Get_ "${IFACE}_ssid")) - sending all interface internet traffic over WAN interface" "$PASS"

					Firewall_NAT delete "$IFACE" 2>/dev/null

					if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.3)" ]
					then
						Routing_NVRAM delete "$IFACE" 2>/dev/null
					else
						Routing_VPNDirector delete "$IFACE" 2>/dev/null
					fi
				fi
			else
				Firewall_NAT delete "$IFACE" 2>/dev/null

				if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.3)" ]
				then
					Routing_NVRAM delete "$IFACE" 2>/dev/null
				else
					Routing_VPNDirector delete "$IFACE" 2>/dev/null
				fi
			fi

			Firewall_DNS create "$IFACE" 2>/dev/null

			if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ALLOWINTERNET")" = "false" ]
			then
				Print_Output true "$IFACE (SSID: $(_NVRAM_Get_ "${IFACE}_ssid")) - allow internet disabled, blocking all interface internet traffic" "$WARN"
				Firewall_BlockInternet create "$IFACE" 2>/dev/null
			else
				Firewall_BlockInternet delete "$IFACE" 2>/dev/null
			fi

			##----------------------------------------##
			## Modified by Martinski W. [2023-Dec-28] ##
			##----------------------------------------##
			if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ONEWAYTOGUEST")" = "true" ] || \
			   [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_TWOWAYTOGUEST")" = "true" ]
			then
				GUESTLANENABLED=true
				Firewall_Rules_ONEorTWO_WAY create "$IFACE" 2>/dev/null
				# Disable Guest Interface ISOLATION #
				if [ "$(_NVRAM_Get_ "${IFACE}_ap_isolate")" != "0" ]
				then
					nvram set "$IFACE"_ap_isolate=0
					WIRELESSRESTART="true"
				fi
			elif [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_CLIENTISOLATION")" = "true" ]
			then
				GUESTLANENABLED=false
				# Enable Guest Interface ISOLATION #
				if [ "$(_NVRAM_Get_ "${IFACE}_ap_isolate")" != "1" ]
				then
					nvram set "$IFACE"_ap_isolate=1
					WIRELESSRESTART="true"
				fi
			fi

			#Set guest interface LAN access to allowed in f/w, prevent creating VLAN#
			if [ "$(_NVRAM_Get_ "${IFACE}_lanaccess")" != "on" ]
			then
				nvram set "$IFACE"_lanaccess=on
				WIRELESSRESTART="true"
			fi

			Routing_RPDB create "$IFACE" 2>/dev/null
			DHCP_Conf create "$IFACE" 2>/dev/null
			sleep 1
		else
			# Remove firewall rules for Guest Interface #
			Firewall_Rules delete "$IFACE" 2>/dev/null

			##-------------------------------------##
			## Added by Martinski W. [2023-Dec-28] ##
			##-------------------------------------##
			Firewall_Rules_ONEorTWO_WAY delete "$IFACE" 2>/dev/null

			Firewall_DNS delete "$IFACE" 2>/dev/null

			Firewall_BlockInternet delete "$IFACE" 2>/dev/null

			Iface_Manage delete "$IFACE" 2>/dev/null

			DHCP_Conf delete "$IFACE" 2>/dev/null

			if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.3)" ]
			then
				Routing_NVRAM delete "$IFACE" 2>/dev/null
			else
				Routing_VPNDirector delete "$IFACE" 2>/dev/null
			fi

			Routing_RPDB delete "$IFACE" 2>/dev/null

			Firewall_NAT delete "$IFACE" 2>/dev/null
		fi
	done

	if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.3)" ]
	then
		Routing_NVRAM save 2>/dev/null
	else
		Routing_VPNDirector save 2>/dev/null
	fi

	DHCP_Conf save 2>/dev/null

	if [ "$GUESTLANENABLED" = "true" ]; then
		Avahi_Conf create
	else
		Avahi_Conf delete
	fi

	if [ "$WIRELESSRESTART" = "true" ]
	then
		nvram commit
		Clear_Lock
		Print_Output true "$SCRIPT_NAME is restarting wireless services now." "$WARN"
		service restart_wireless >/dev/null 2>&1
	elif [ "$WIRELESSRESTART" = "false" ]
	then
		Execute_UserScripts
		Iface_BounceClients
	fi

	NetworkMap_Apply

	Print_Output true "$SCRIPT_NAME $SCRIPT_VERSION completed successfully" "$PASS"
	Clear_Lock
}

Execute_UserScripts()
{
	FILES="$USER_SCRIPT_DIR/*.sh"
	for shFile in $FILES
	do
		if [ -f "$shFile" ]
		then
			Print_Output true "Executing user script: $shFile" "$PASS"
			sh "$shFile"
		fi
	done
}

### Code adapted from firmware WebUI function, credit to @RMerlin ###
Generate_QRCode()
{
	QRGUEST_WL="$1"
	QRSSID="S:$(_NVRAM_Get_ "$QRGUEST_WL"_ssid | sed 's/[\\":;,]/\\$&/g');"
	QRAUTHMODE="$(_NVRAM_Get_ "$QRGUEST_WL"_auth_mode_x)"

	if [ "$QRAUTHMODE" = 'psk' ]  || \
	   [ "$QRAUTHMODE" = 'psk2' ]  || \
	   [ "$QRAUTHMODE" = 'sae' ]    || \
	   [ "$QRAUTHMODE" = 'pskpsk2' ] || \
	   [ "$QRAUTHMODE" = 'psk2sae' ]
	then
		QRTYPE="T:WPA;"
		QRPASS="P:$(_NVRAM_Get_ "$QRGUEST_WL"_wpa_psk | sed 's/[\\":;,]/\\$&/g');"
	elif [ "$QRAUTHMODE" = "open" ] && [ "$(_NVRAM_Get_ "$QRGUEST_WL"_wep_x)" -eq 0 ]
	then
		QRTYPE="T:;"
		QRPASS="P:;"
	elif [ "$QRAUTHMODE" = "shared" ] || [ "$QRAUTHMODE" = "open" ]
	then
		QRTYPE="T:WEP;"
		QRKEYINDEX=$(_NVRAM_Get_ "$QRGUEST_WL"_key)
		QRPASS="$(_NVRAM_Get_ "$QRGUEST_WL"_key"$QRKEYINDEX");"
	else
		QRSSID=""  #UNSUPPORTED#
	fi

	if [ "$(_NVRAM_Get_ "$QRGUEST_WL"_closed)" -eq 1 ]
	then
		QRHIDE="H:true;"
	fi

	if [ -n "$QRSSID" ]
	then
		qrencode -t ANSI -o - "WIFI:${QRTYPE}${QRSSID}${QRPASS}${QRHIDE};"
	else
		printf "\nQR Code generation NOT supported for this guest network. Please check configuration.\n"
	fi
	QRTYPE=""
	QRSSID=""
	QRPASS=""
	QRHIDE=""
}

Shortcut_Script()
{
	case $1 in
		create)
			if [ -d /opt/bin ] && \
			   [ -s "$SCRIPT_FPATH" ] && \
			   [ ! -f "/opt/bin/$SCRIPT_NAME" ]
			then
				ln -s "$SCRIPT_FPATH" /opt/bin
				chmod 0755 "/opt/bin/$SCRIPT_NAME"
			fi
		;;
		delete)
			if [ -f "/opt/bin/$SCRIPT_NAME" ]
			then
				rm -f "/opt/bin/$SCRIPT_NAME"
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2023-Nov-20] ##
##----------------------------------------##
PressEnter()
{
   ! "$isInteractive" && return 0
   printf "Press <Enter> to continue..."
   read -rs theKey ; echo
}

##-------------------------------------##
## Added by Martinski W. [2025-Oct-26] ##
##-------------------------------------##
_CenterTextStr_()
{
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
       ! echo "$2" | grep -qE "^[1-9][0-9]+$"
    then echo ; return 1
    fi
    local stringLen="${#1}"
    local space1Len="$((($2 - stringLen)/2))"
    local space2Len="$space1Len"
    local totalLen="$((space1Len + stringLen + space2Len))"

    if [ "$totalLen" -lt "$2" ]
    then space2Len="$((space2Len + 1))"
    elif [ "$totalLen" -gt "$2" ]
    then space1Len="$((space1Len - 1))"
    fi
    if [ "$space1Len" -gt 0 ] && [ "$space2Len" -gt 0 ]
    then printf "%*s%s%*s" "$space1Len" '' "$1" "$space2Len" ''
    else printf "%s" "$1"
    fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-Oct-26] ##
##----------------------------------------##
ScriptHeader()
{
	clear
	local spaceLen=46  colorCT
	[ "$SCRIPT_BRANCH" = "master" ] && colorCT="$GRNct" || colorCT="$MGNTct"
	echo
	printf "${BOLD}####################################################${CLRct}\n"
	printf "${BOLD}##         __     __          ______  _           ##${CLRct}\n"
	printf "${BOLD}##         \ \   / /         |  ____|(_)          ##${CLRct}\n"
	printf "${BOLD}##          \ \_/ /__ _  ____| |__    _           ##${CLRct}\n"
	printf "${BOLD}##           \   // _  ||_  /|  __|  | |          ##${CLRct}\n"
	printf "${BOLD}##            | || (_| | / / | |     | |          ##${CLRct}\n"
	printf "${BOLD}##            |_| \__,_|/___||_|     |_|          ##${CLRct}\n"
	printf "${BOLD}##                                                ##${CLRct}\n"
	printf "${BOLD}## ${GRNct}%s${CLRct}${BOLD} ##${CLRct}\n" "$(_CenterTextStr_ "$versionMod_TAG" "$spaceLen")"
	printf "${BOLD}## ${colorCT}%s${CLRct}${BOLD} ##${CLRct}\n" "$(_CenterTextStr_ "$branchxStr_TAG" "$spaceLen")"
	printf "${BOLD}##                                                ##${CLRct}\n"
	printf "${BOLD}##       https://github.com/AMTM-OSR/YazFi        ##${CLRct}\n"
	printf "${BOLD}## Forked from: https://github.com/jackyaz/YazFi  ##${CLRct}\n"
	printf "${BOLD}##                                                ##${CLRct}\n"
	printf "${BOLD}####################################################${CLRct}\n\n"
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_HandleInvalidMenuOption_()
{
	[ -n "$menuOption" ] && \
	printf "\n ${REDct}INVALID input [$menuOption]${CLRct}"
	printf "\n Please choose a valid option.\n\n"
	PressEnter
}

##----------------------------------------##
## Modified by Martinski W. [2026-Aug-21] ##
##----------------------------------------##
MainMenu()
{
	local menuOption  configChangesMade=false
	local TwoWayToGuestENABLED  OneWayToGuestENABLED

	if _Check_OneWayToGuest_Enabled_
	then OneWayToGuestENABLED=true
	else OneWayToGuestENABLED=false
	fi
	if _Check_TwoWayToGuest_Enabled_
	then TwoWayToGuestENABLED=true
	else TwoWayToGuestENABLED=false
	fi

	ScriptHeader

	printf " WebUI for %s is available at:\n ${SETTING}%s${CLRct}\n\n" "$SCRIPT_NAME" "$(Get_WebUI_URL)"

	printf "  ${GRNct}1${CLRct}.  Apply %s settings\n\n" "$SCRIPT_NAME"
	printf "  ${GRNct}2${CLRct}.  Show connected clients using %s\n\n" "$SCRIPT_NAME"
	printf "  ${GRNct}3${CLRct}.  Edit %s config\n" "$SCRIPT_NAME"
	printf "  ${GRNct}4${CLRct}.  Edit Guest Network config (SSID + passphrase)\n\n"

	if "$OneWayToGuestENABLED" || "$TwoWayToGuestENABLED"
	then
		printf " ${GRNct}rt${CLRct}.  Set Guest Network One/Two-Way Routing Type\n\n"
	else
		printf " ${GRAYEDct}rt${CLRct}.  ${GRAYEDct}Set Guest Network One/Two-Way Routing Type${CLRct}\n\n"
	fi

	if [ -x /opt/bin/opkg ] && [ -x /opt/bin/qrencode ]
	then
		printf " ${GRNct}qr${CLRct}.  Show QR Code for Guest Network\n\n"
	else
		printf " ${GRAYEDct}qr${CLRct}.  ${REDct}QR Code generator NOT available${CLRct}\n\n"
	fi
	printf "  ${GRNct}u${CLRct}.  Check for updates\n"
	printf " ${GRNct}uf${CLRct}.  Update %s with latest version (force update)\n\n" "$SCRIPT_NAME"
	printf "  ${GRNct}d${CLRct}.  Generate %s diagnostics\n\n" "$SCRIPT_NAME"
	printf "  ${GRNct}e${CLRct}.  Exit %s\n\n" "$SCRIPT_NAME"
	printf "  ${GRNct}z${CLRct}.  Uninstall %s\n\n" "$SCRIPT_NAME"
	printf "${BOLD}#############################################${CLRct}\n\n"

	while true
	do
		printf " Choose an option:  "
		read -r menuOption

		case "$menuOption" in
			1)
				printf "\n"
				if Check_Lock menu
				then
					Config_Networks
					Clear_Lock
				fi
				PressEnter
				break
			;;
			2)
				printf "\n"
				Menu_Status
				PressEnter
				break
			;;
			3)
				printf "\n"
				if Check_Lock menu
				then
					configChangesMade=false
					Menu_Edit
					if "$configChangesMade"
					then . "$SCRIPT_CONF"
					fi
				else
					PressEnter
				fi
				break
			;;
			4)
				printf "\n"
				if Check_Lock menu
				then
					Menu_GuestConfig
				else
					PressEnter
				fi
				break
			;;
			rt)
				if "$OneWayToGuestENABLED" || "$TwoWayToGuestENABLED"
				then
					configChangesMade=false
					_Menu_OneTwoWayToGuest_RoutingType_
					if "$configChangesMade"
					then . "$SCRIPT_CONF"
					fi
				else
					printf "\n ${REDct}Guest Network One/Two-Way Routing Type is NOT available.${CLRct}"
					printf "\n All Guest Network One/Two-Way options are found disabled.\n\n"
					PressEnter
				fi
				break
			;;
			qr)
				if [ -x /opt/bin/opkg ] && [ -x /opt/bin/qrencode ]
				then
					Menu_QRCode
				else
					printf "\n ${REDct}QR Code generator is NOT available${CLRct}\n\n"
					PressEnter
				fi
				break
			;;
			u)
				printf "\n"
				if Check_Lock menu
				then
					Update_Version
					Clear_Lock
				fi
				PressEnter
				break
			;;
			uf)
				printf "\n"
				if Check_Lock menu
				then
					Update_Version force
					Clear_Lock
				fi
				PressEnter
				break
			;;
			d)
				ScriptHeader
				Menu_Diagnostics
				PressEnter
				break
			;;
			e)
				ScriptHeader
				printf "\n${BOLD}Thanks for using %s!${CLRct}\n\n\n" "$SCRIPT_NAME"
				exit 0
			;;
			z)
				while true
				do
					printf "\n${BOLD}Are you sure you want to uninstall %s? (y/n)${CLRct}  " "$SCRIPT_NAME"
					read -r confirm
					case "$confirm" in
						y|Y)
							Menu_Uninstall
							exit 0
						;;
						*)
							break
						;;
					esac
				done
			;;
			*)
				_HandleInvalidMenuOption_
				break
			;;
		esac
	done

	MainMenu
}

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
Check_Requirements()
{
	local CHECKSFAILED=false

	if [ "$(_NVRAM_Get_ sw_mode)" -ne 1 ]
	then
		CHECKSFAILED=true
		Print_Output false "Device is not running in Router Mode - non-router modes are not supported." "$ERR"
	fi

	if [ "$(_NVRAM_Get_ jffs2_scripts)" -ne 1 ]
	then
		nvram set jffs2_scripts=1
		nvram commit
		Print_Output true "Custom JFFS Scripts enabled" "$WARN"
	fi

	if [ "$(_NVRAM_Get_ wl_radio)" -eq 0 ]  && \
	   [ "$(_NVRAM_Get_ wl0_radio)" -eq 0 ] && \
	   [ "$(_NVRAM_Get_ wl1_radio)" -eq 0 ]
	then
		CHECKSFAILED=true
		Print_Output false "No wireless radios are enabled!" "$ERR"
	fi

	if ! _Firmware_Support_Check_
	then CHECKSFAILED=true
	fi

	if ! _Firmware_Version_WebUI_
	then CHECKSFAILED=true
	fi

	if [ "$CHECKSFAILED" = "false" ]
	then return 0
	else return 1
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
Menu_Install()
{
	ScriptHeader
	Print_Output true "Welcome to $SCRIPT_NAME $SCRIPT_VERSION, a script by JackYaz" "$PASS"
	sleep 1

	Print_Output true "Checking if your router meets the requirements for $SCRIPT_NAME" "$PASS"

	if ! Check_Requirements
	then
		Print_Output true "Requirements for $SCRIPT_NAME not met, please see above for the reason(s)" "$CRIT"
		PressEnter ; echo
		Clear_Lock
		rm -f "$SCRIPT_FPATH"
		exit 1
	fi

	if [ -x /opt/bin/opkg ] && [ ! -s /opt/bin/qrencode ]
	then
		opkg update
		opkg install qrencode
	fi
	Create_Dirs
	Create_Symlinks

	Update_File shared-jy.tar.gz
	Update_File YazFi_www.asp
	Update_File YazFi_networkmap.js

	if ! Conf_Exists
	then
		Config_Download "$SCRIPT_CONF" && . "$SCRIPT_CONF"
	else
		Print_Output false "Existing $SCRIPT_CONF found. This will be kept by $SCRIPT_NAME" "$WARN"
		Config_Download "${SCRIPT_CONF}.example"
	fi

	Update_File README.md

	Shortcut_Script create
	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Set_Version_Custom_Settings server "$SCRIPT_VERSION"
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_DNSMASQ create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Auto_NetworkMapServiceEventEnd create 2>/dev/null
	Auto_ServiceStart create 2>/dev/null
	Auto_OpenVPNEvent create 2>/dev/null
	NetworkMap_Apply

	Print_Output false "You can access ${SCRIPT_NAME}'s configuration via the Guest Networks section of the WebUI" "$BOLD"
	Print_Output false "Alternatively, use ${SCRIPT_NAME}'s menu via AMTM, with $SCRIPT_FPATH or simply $SCRIPT_NAME" "$BOLD"
	Clear_Lock
	PressEnter
	Download_File "$SCRIPT_REPO" LICENSE "${SCRIPT_DIR}/LICENSE"
	MainMenu
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-18] ##
##-------------------------------------##
Menu_Startup()
{
	sleep 15
	if [ -x /opt/bin/opkg ] && [ ! -s /opt/bin/qrencode ]
	then
		opkg update
		opkg install qrencode
	fi
	Create_Dirs
	Create_Symlinks
	Auto_Cron create 2>/dev/null
	Auto_NetworkMapServiceEventEnd create 2>/dev/null
	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Mount_WebUI
	NetworkMap_Apply
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Menu_Edit()
{
	local exitMenu=false  textEditor=""
	if ! Conf_Exists
	then
		Config_Download "$SCRIPT_CONF" && . "$SCRIPT_CONF"
	fi

	printf "\n ${BOLD}Text editors available:${CLRct}\n\n"
	printf "  ${GRNct}1${CLRct}. nano (recommended for beginners)\n"
	printf "  ${GRNct}2${CLRct}. vi\n\n"
	printf "  ${GRNct}e${CLRct}. Back to main menu\n"

	while true
	do
		printf "\n ${BOLD}Choose an option:${CLRct}  "
		read -r editorOption
		case "$editorOption" in
			1) textEditor="nano -K" ; break
			   ;;
			2) textEditor="vi" ; break
			   ;;
			e) exitMenu=true ; break
			   ;;
			*)
				if [ -z "$editorOption" ]
				then exitMenu=true ; break
				fi
				printf "\n Please choose a valid option.\n\n"
				;;
		esac
	done

	if [ "$exitMenu" = "false" ]
	then
		cp -fp "$SCRIPT_CONF" "${SCRIPT_CONF}.bak"
		$textEditor "$SCRIPT_CONF"

		if ! diff -q "$SCRIPT_CONF" "${SCRIPT_CONF}.bak" >/dev/null 2>&1
		then
			configChangesMade=true
			printf "\n ${BOLD}${MGNTct}Once you have completed all changes, please remember"
			printf "\n to apply all YazFi settings so they can take effect.${CLRct}\n\n"
			PressEnter
		fi
	fi
	Clear_Lock
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Menu_GuestConfig()
{
	local ifaceCount  addListGap  exitMenu=false
	local IFaceID  IFaceVar  selectedIFACE  isIFACE_VALID
	local guestNAMEstr  guestSSIDstr  guestPSWDstr  validOptions=""
    local exitRegExp="([Ee](xit)?|EXIT)"  changesMade=false

	ScriptHeader
	printf "\n ${BOLD}Select a Guest Network to configure:${CLRct}\n\n"

	ifaceCount=1
	addListGap=false

	for IFaceID in $IFACELIST_ORIG
	do
		IFaceVar="$(Get_Iface_Var "$IFaceID")"
		if [ "$(eval echo '$'"${IFaceVar}_ENABLED")" = "true" ] && \
		   Validate_IFACE_Enabled "$IFaceID" silent
		then
			if "$addListGap"
			then addListGap=false ; [ -n "$validOptions" ] && echo
			fi
			validOptions="${validOptions:+$validOptions }$ifaceCount"
			printf "  ${GRNct}%s${CLRct}. %s (SSID: %s)\n" "$ifaceCount" "$(Menu_Get_Guest_Name "$IFaceID")" "$(_NVRAM_Get_ "${IFaceID}_ssid")"
		fi
		if [ "$((ifaceCount % 3))" -eq 0 ]
		then addListGap=true
		fi
		ifaceCount="$((ifaceCount + 1))"
	done
	printf "\n  ${GRNct}e${CLRct}. Back to main menu\n"

	while true
	do
		selectedIFACE=""
		isIFACE_VALID=false

		printf "\n ${BOLD}Choose an option:${CLRct}  "
		read -r selectedGuest

		case "$selectedGuest" in
			1|2|3|4|5|6|7|8|9|10|11|12)
				selectedIFACE="$(echo "$IFACELIST_ORIG" | awk -F ' ' '{print $'"$selectedGuest"'}')" ;;
			e)
				exitMenu=true ; break ;;
			*)
				printf "\n Please choose a valid option\n" ;;
		esac

		if [ -z "$selectedIFACE" ]
		then
			echo "$selectedGuest" | grep -qE '^([1-9]|1[0-2])$' && \
			printf "\n Please choose a valid option\n"
		else
			if ! Validate_IFACE_Support "$selectedIFACE" silent
			then
				printf "\n The Guest Network [${MGNTct}%s${CLRct}] is NOT supported on this router." "$selectedIFACE"
				printf "\n Please choose a different option.\n"
			elif ! Validate_IFACE_Enabled "$selectedIFACE" silent
			then
				printf "\n The Guest Network [${MGNTct}%s${CLRct}] is NOT enabled on this router." "$selectedIFACE"
				printf "\n Please choose a different option.\n"
			else
				isIFACE_VALID=true ; break
			fi
		fi
	done

	if [ "$exitMenu" != "true" ] && "$isIFACE_VALID"
	then
		guestNAMEstr="$(Menu_Get_Guest_Name "$selectedIFACE")"
		guestSSIDstr="$(_NVRAM_Get_ "${selectedIFACE}_ssid")"
		guestPSWDstr="$(_NVRAM_Get_ "${selectedIFACE}_wpa_psk")"

		while true
		do
			ScriptHeader
			printf "\n ${GRNct}%s [%s]${CLRct}\n" "$guestNAMEstr" "$selectedIFACE"
			printf "\n ${BOLD}Available options:${CLRct}\n\n"
			printf "  ${GRNct}1${CLRct}. Set SSID (current: ${GRNct}%s${CLRct})\n" "$guestSSIDstr"
			printf "  ${GRNct}2${CLRct}. Set passphrase (current: ${GRNct}%s${CLRct})\n\n" "$guestPSWDstr"
			printf "  ${GRNct}e${CLRct}. Go back\n"

			printf "\n ${BOLD}Choose an option:${CLRct}  "
			read -r guestoption

			case "$guestoption" in
				1)
					printf "\n ${BOLD}Please enter your new SSID:${CLRct}  "
					read -r newssid
					if echo "$newssid" | grep -qE "^${exitRegExp}$"
					then continue
					fi
					newssidclean="$newssid"
					if ! Validate_String "$newssid"
					then
						newssidclean="$(echo "$newssid" | sed 's/[^a-zA-Z0-9]//g')"
					fi
					nvram set "${selectedIFACE}_ssid"="$newssidclean"
					nvram commit
					changesMade=true
				;;
				2)
					while true
					do
						printf "\n ${BOLD}Available options:${CLRct}\n\n"
						printf "  ${GRNct}1${CLRct}. Generate random passphrase\n"
						printf "  ${GRNct}2${CLRct}. Manually set passphrase\n\n"
						printf "  ${GRNct}e${CLRct}. Go back\n"
						printf "\n ${BOLD}Choose an option:${CLRct}  "
						read -r passoption
						case "$passoption" in
							1)
								validpasslength=""
								while true
								do
									printf "\n ${BOLD}How many characters? [8-32]${CLRct}  "
									read -r passlength
									if echo "$passlength" | grep -qE "^${exitRegExp}$"
									then
										break
									elif Validate_Number "" "$passlength" silent
									then
										if [ "$passlength" -le 32 ] && [ "$passlength" -ge 8 ]
										then
											validpasslength="$passlength"
											break
										else
											printf "\n Please choose a number between 8 and 32\n\n"
										fi
									else
										printf "\n Please choose a valid number\n\n"
									fi
								done

								if [ -n "$validpasslength" ]
								then
									newpassphrase="$(Generate_Random_String "$validpasslength")"
									newpassphraseclean="$(echo "$newpassphrase" | sed 's/[^a-zA-Z0-9]//g')"
									Set_WiFi_Passphrase "$selectedIFACE" "$newpassphraseclean"
									changesMade=true
									break
								fi
							;;
							2)
								printf "\n ${BOLD}Please enter your new passphrase:${CLRct}  "
								read -r newpassphrase
								if echo "$newpassphrase" | grep -qE "^${exitRegExp}$"
								then continue
								fi
								newpassphraseclean="$newpassphrase"
								if ! Validate_String "$newpassphrase"
								then
									newpassphraseclean="$(echo "$newpassphrase" | sed 's/[^a-zA-Z0-9]//g')"
								fi
								Set_WiFi_Passphrase "$selectedIFACE" "$newpassphraseclean"
								changesMade=true
								break
							;;
							e)
								break
							;;
							*)
								printf "\n Please choose a valid option\n\n"
								PressEnter
							;;
						esac
					done
				;;
				e)
					if "$changesMade"
					then
						while true
						do
							printf "\n ${BOLD}Do you want to restart wireless services now? (y/n)${CLRct}  "
							read -r confirmrestart
							case "$confirmrestart" in
								y|Y)
									Clear_Lock
									service restart_wireless >/dev/null 2>&1
									break
								;;
								*)
									break
								;;
							esac
						done
					fi
					ScriptHeader
					break
				;;
				*)
					printf "\n Please choose a valid option.\n\n"
					PressEnter
				;;
			esac
		done

		Menu_GuestConfig
	fi
	Clear_Lock
}

##----------------------------------------##
## Modified by Martinski W. [2026-Apr-15] ##
##----------------------------------------##
Menu_QRCode()
{
	local ifaceCount  addListGap  exitMenu=false  validOptions=""
	local IFaceID  IFaceVar  selectedIFACE  isIFACE_VALID

	ScriptHeader
	printf "\n ${BOLD}Select a Guest Network for QR Code:${CLRct}\n\n"

	ifaceCount=1
	addListGap=false

	for IFaceID in $IFACELIST_ORIG
	do
		IFaceVar="$(Get_Iface_Var "$IFaceID")"
		if [ "$(eval echo '$'"${IFaceVar}_ENABLED")" = "true" ] && \
		   Validate_IFACE_Enabled "$IFaceID" silent
		then
			if "$addListGap"
			then addListGap=false ; [ -n "$validOptions" ] && echo
			fi
			validOptions="${validOptions:+$validOptions }$ifaceCount"
			printf "  ${GRNct}%s${CLRct}. %s (SSID: %s)\n" "$ifaceCount" "$(Menu_Get_Guest_Name "$IFaceID")" "$(_NVRAM_Get_ "${IFaceID}_ssid")"
		fi
		if [ "$((ifaceCount % 3))" -eq 0 ]
		then addListGap=true
		fi
		ifaceCount="$((ifaceCount + 1))"
	done
	printf "\n  ${GRNct}e${CLRct}. Back to main menu\n"

	while true
	do
		selectedIFACE=""
		isIFACE_VALID=false

		printf "\n ${BOLD}Choose an option:${CLRct}  "
		read -r selectedGuest

		case "$selectedGuest" in
			1|2|3|4|5|6|7|8|9|10|11|12)
				selectedIFACE="$(echo "$IFACELIST_ORIG" | awk -F ' ' '{print $'"$selectedGuest"'}')" ;;
			e)
				exitMenu=true ; break ;;
			*)
				printf "\n Please choose a valid option\n" ;;
		esac

		if [ -z "$selectedIFACE" ]
		then
			echo "$selectedGuest" | grep -qE '^([1-9]|1[0-2])$' && \
			printf "\n Please choose a valid option\n"
		else
			if ! Validate_IFACE_Support "$selectedIFACE" silent
			then
				printf "\n The Guest Network [${MGNTct}%s${CLRct}] is NOT supported on this router." "$selectedIFACE"
				printf "\n Please choose a different option.\n"
			elif ! Validate_IFACE_Enabled "$selectedIFACE" silent
			then
				printf "\n The Guest Network [${MGNTct}%s${CLRct}] is NOT enabled on this router." "$selectedIFACE"
				printf "\n Please choose a different option.\n"
			else
				isIFACE_VALID=true ; break
			fi
		fi
	done

	"$exitMenu" && return 0

	if [ -x /opt/bin/opkg ] && [ -x /opt/bin/qrencode ]
	then
		printf "\n"
		Generate_QRCode "$selectedIFACE"
	else
		printf "\n ${REDct}QR Code generator is NOT available${CLRct}\n"
	fi
	echo ; PressEnter
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_OneWayToGuest_RoutingType_()
{
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
    then return 1
    fi
	local modeValue  IFaceVar

	IFaceVar="$(Get_Iface_Var "$2")_ONEWAYTOGUEST_MODE"
	modeValue="$(eval echo '$'"$IFaceVar")"

	case "$1" in
		check)
			echo "${modeValue:=NAT}"
			;;
		update)
			if [ "$modeValue" != "NAT" ]
			then modeValue="NAT"
			else modeValue="FILTER"
			fi
			sed -i "s/^${IFaceVar}=.*/${IFaceVar}=$modeValue/" "$SCRIPT_CONF"
			;;
	esac
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_TwoWayToGuest_RoutingType_()
{
    if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
    then return 1
    fi
	local modeValue  IFaceVar

	IFaceVar="$(Get_Iface_Var "$2")_TWOWAYTOGUEST_MODE"
	modeValue="$(eval echo '$'"$IFaceVar")"

	case "$1" in
		check)
			echo "${modeValue:=NAT}"
			;;
		update)
			if [ "$modeValue" != "NAT" ]
			then modeValue="NAT"
			else modeValue="FILTER"
			fi
			sed -i "s/^${IFaceVar}=.*/${IFaceVar}=$modeValue/" "$SCRIPT_CONF"
			;;
	esac
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_Check_OneWayToGuest_Enabled_()
{
	local IFaceID  IFaceVar  isOptionEnabled=false
	for IFaceID in $IFACELIST
	do
		IFaceVar="$(Get_Iface_Var "$IFaceID")"
		if [ "$(eval echo '$'"${IFaceVar}_ENABLED")" = "true" ] && \
		   [ "$(eval echo '$'"${IFaceVar}_ONEWAYTOGUEST")" = "true" ] && \
		   Validate_IFACE_Enabled "$IFaceID" silent
		then
			isOptionEnabled=true
			break
		fi
	done
	"$isOptionEnabled" && return 0 || return 1
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_Check_TwoWayToGuest_Enabled_()
{
	local IFaceID  IFaceVar  isOptionEnabled=false
	for IFaceID in $IFACELIST
	do
		IFaceVar="$(Get_Iface_Var "$IFaceID")"
		if [ "$(eval echo '$'"${IFaceVar}_ENABLED")" = "true" ] && \
		   [ "$(eval echo '$'"${IFaceVar}_TWOWAYTOGUEST")" = "true" ] && \
		   Validate_IFACE_Enabled "$IFaceID" silent
		then
			isOptionEnabled=true
			break
		fi
	done
	"$isOptionEnabled" && return 0 || return 1
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_Menu_OneTwoWayToGuest_RoutingType_()
{
	local ifaceCount  addListGap  exitMenu=false
	local theWayToGuestModeStr  validOptions=""
	local IFaceID  IFaceVar  selectedIFACE  isIFACE_VALID
	local theONE_WAYtoGUEST  theTWO_WAYtoGUEST
	local OneWayToGuestMODE  TwoWayToGuestMODE

	ScriptHeader
	printf "\n ${BOLD}Set the Guest Network One/Two-Way Routing Type:${CLRct}\n\n"

	ifaceCount=1
	addListGap=false
	. "$SCRIPT_CONF"

	for IFaceID in $IFACELIST_ORIG
	do
		IFaceVar="$(Get_Iface_Var "$IFaceID")"
		theONE_WAYtoGUEST="$(eval echo '$'"${IFaceVar}_ONEWAYTOGUEST")"
		theTWO_WAYtoGUEST="$(eval echo '$'"${IFaceVar}_TWOWAYTOGUEST")"
		OneWayToGuestMODE="$(eval echo '$'"${IFaceVar}_ONEWAYTOGUEST_MODE")"
		TwoWayToGuestMODE="$(eval echo '$'"${IFaceVar}_TWOWAYTOGUEST_MODE")"

		if [ "$(eval echo '$'"${IFaceVar}_ENABLED")" = "true" ] && \
		   { [ "$theONE_WAYtoGUEST" = "true" ] || [ "$theTWO_WAYtoGUEST" = "true" ]
		   } && Validate_IFACE_Enabled "$IFaceID" silent
		then
			if "$addListGap"
			then addListGap=false ; [ -n "$validOptions" ] && echo
			fi
			validOptions="${validOptions:+$validOptions }$ifaceCount"

			if [ "$theONE_WAYtoGUEST" = "true" ]
			then
				if [ "$OneWayToGuestMODE" = "NAT" ]
				then theWayToGuestModeStr="${SETTING}One-Way${CLRct}: ${GRNct}NAT PostRouting${CLRct}"
				else theWayToGuestModeStr="${SETTING}One-Way${CLRct}: ${GRNct}FILTER Forward${CLRct}"
				fi
			elif [ "$theTWO_WAYtoGUEST" = "true" ]
			then
				if [ "$TwoWayToGuestMODE" = "NAT" ]
				then theWayToGuestModeStr="${SETTING}Two-Way${CLRct}: ${GRNct}NAT PostRouting${CLRct}"
				else theWayToGuestModeStr="${SETTING}Two-Way${CLRct}: ${GRNct}FILTER Forward${CLRct}"
				fi
			fi

			printf "  ${GRNct}%s${CLRct}. %s (SSID: %s)\n" "$ifaceCount" "$(Menu_Get_Guest_Name "$IFaceID")" "$(_NVRAM_Get_ "${IFaceID}_ssid")"
			printf "     [$theWayToGuestModeStr]\n"
        fi

		if [ "$((ifaceCount % 3))" -eq 0 ]
		then addListGap=true
		fi
		ifaceCount="$((ifaceCount + 1))"
	done
	printf "\n  ${GRNct}e${CLRct}. Back to main menu\n"

	while true
	do
		selectedIFACE=""
		isIFACE_VALID=false

		printf "\n ${BOLD}Choose an option:${CLRct}  "
		read -r selectedGuest

		case "$selectedGuest" in
			1|2|3|4|5|6|7|8|9|10|11|12)
				selectedIFACE="$(echo "$IFACELIST_ORIG" | awk -F ' ' '{print $'"$selectedGuest"'}')" ;;
			e)
				exitMenu=true ; break ;;
			*)
				printf "\n Please choose a valid option\n" ;;
		esac

		if [ -z "$selectedIFACE" ]
		then
			echo "$selectedGuest" | grep -qE '^([1-9]|1[0-2])$' && \
			printf "\n Please choose a valid option\n"
		else
			if ! Validate_IFACE_Support "$selectedIFACE" silent
			then
				printf "\n The Guest Network [${MGNTct}%s${CLRct}] is NOT supported on this router." "$selectedIFACE"
				printf "\n Please choose a different option.\n"
			elif ! Validate_IFACE_Enabled "$selectedIFACE" silent
			then
				printf "\n The Guest Network [${MGNTct}%s${CLRct}] is NOT enabled on this router." "$selectedIFACE"
				printf "\n Please choose a different option.\n"
			elif ! echo "$validOptions" | grep -qw "$selectedGuest"
			then
				printf "\n The Guest Network [${MGNTct}%s${CLRct}] has One/Two-Way option DISABLED." "$selectedIFACE"
				printf "\n Please choose a different option.\n"
			else
				isIFACE_VALID=true
			fi
		fi
        break
	done

	if "$exitMenu"
	then
		"$configChangesMade" && \
		{
		   printf "\n ${BOLD}${MGNTct}Once you have completed all changes, please remember"
		   printf "\n to apply all YazFi settings so they can take effect.${CLRct}\n\n"
		   PressEnter
		}
		return 0
	fi

	if "$isIFACE_VALID"
	then
		configChangesMade=true
		IFaceVar="$(Get_Iface_Var "$selectedIFACE")"
		theONE_WAYtoGUEST="$(eval echo '$'"${IFaceVar}_ONEWAYTOGUEST")"
		theTWO_WAYtoGUEST="$(eval echo '$'"${IFaceVar}_TWOWAYTOGUEST")"

        if [ "$theONE_WAYtoGUEST" = "true" ]
        then _OneWayToGuest_RoutingType_ update "$selectedIFACE"
        elif [ "$theTWO_WAYtoGUEST" = "true" ]
        then _TwoWayToGuest_RoutingType_ update "$selectedIFACE"
        fi
	else
		echo ; PressEnter
	fi
	_Menu_OneTwoWayToGuest_RoutingType_
}

##-------------------------------------##
## Added by Martinski W. [2026-Aug-20] ##
##-------------------------------------##
_ConnectedClientsCheckRunning_()
{
	local procCount="$(top -bn1 | grep -cE "/jffs/scripts[/]$SCRIPT_NAME service_event start YazFiconnectedclients")"
	if [ "$procCount" -gt 6 ]
	then return 0
	else return 1
	fi
}

## This function suggested by @HuskyHerder, code inspired by @ColinTaylor's wireless monitor script ##
##----------------------------------------##
## Modified by Martinski W. [2024-Jan-03] ##
##----------------------------------------##
Menu_Status()
{
	renice 15 $$
	STATUSOUTPUTFILE="$SCRIPT_DIR/.connectedclients"
	TMPSTATUSOUTPUTFILE="/tmp/YazFi_$$.connectedclients"
	printf '' > "$STATUSOUTPUTFILE"
	. "$SCRIPT_CONF"

	if [ -x /opt/bin/opkg ] && [ ! -s /opt/bin/dig ]
	then
		opkg update
		opkg install bind-dig
	fi

	local NoARGs=false
	if [ $# -eq 0 ] || [ -z "$1" ] ; then NoARGs=true ; fi

	"$NoARGs" && \
	{
	   ScriptHeader
	   printf " ${BOLD}${PASS}Querying router for connected WiFi clients...${CLRct}\n\n"
	}
	printf "INTERFACE,HOSTNAME,IP,MAC,CONNECTED,RX,TX,RSSI,PHY\n" > "$TMPSTATUSOUTPUTFILE"

	##----------------------------------------##
	## Modified by Martinski W. [2023-Dec-06] ##
	##----------------------------------------##
	ARP_CACHE="/proc/net/arp"
	NOT_LANIP="grep -vF \"$(echo "$LAN_IPaddr" | cut -d'.' -f1-3).\""
	DNSMASQ_LEASES="/var/lib/misc/dnsmasq.leases"

	for IFACE in $IFACELIST
	do
		if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ENABLED")" = "true" ] && \
		   Validate_IFACE_Enabled "$IFACE" silent
		then
			"$NoARGs" && \
			{
			   printf "%114s\n\n" ' ' | tr ' ' '_'
			   printf "   ${BOLD}SSID: ${GRNct}%s${CLRct}\n" "$(_NVRAM_Get_ "${IFACE}_ssid")"
			   printf "   ${BOLD}NETWORK: ${GRNct}%s${CLRct}\n" "$(Menu_Get_Guest_Name "$IFACE")"
			   printf "   ${BOLD}INTERFACE: ${GRNct}%s${CLRct}\n\n" "$IFACE"
			}
			IFACE_MACS="$(wl -i "$IFACE" assoclist)"
			if [ "$IFACE_MACS" != "" ]
			then
				"$NoARGs" && \
				{
				  printf "${BOLD}%-32s%-18s%-20s%-15s%-15s%-10s%-5s${CLRct}\n" "HOSTNAME" "IP" "MAC" "CONNECTED" "RX/TX" "RSSI" "PHY"
				  printf "${BOLD}%-32s%-18s%-20s%-15s%-15s%-10s%-5s${CLRct}\n" \
				  "------------------------------" "---------------" "-----------------" "-------------" "-------------" "--------" "----"
				}
				IFS=$'\n'
				for GUEST_MAC in $IFACE_MACS
				do
					GUEST_MACADDR="$(echo "$GUEST_MAC" | awk '{print $2}')"

					##----------------------------------------##
					## Modified by Martinski W. [2023-Dec-06] ##
					##----------------------------------------##
					GUEST_ARPCOUNT="$(grep -ic "$GUEST_MACADDR" "$ARP_CACHE")"
					[ "$GUEST_ARPCOUNT" -eq 0 ] && continue

					GUEST_ARPINFO="$(grep -i "$GUEST_MACADDR" "$ARP_CACHE" | grep "$IFACE" | eval "$NOT_LANIP")"
					GUEST_IPADDR="$(echo "$GUEST_ARPINFO" | awk -F ' ' '{print $1}')"
					GUEST_ARPFLAG="$(echo "$GUEST_ARPINFO" | awk -F ' ' '{print $3}')"

					#------------------------------------------------------------------#
					# Modified by Martinski W. [2023-Dec-06].
					# The Guest Network client has an ARP entry marked as "incomplete"
					# so one option is to just skip the client here as we used to do.
					# However, sometimes the ARP Cache may not always be up to date,
					# so we decide to continue after this point to find out if we can
					# get the required IP address & Hostname info from other sources.
					#------------------------------------------------------------------#
					[ "$GUEST_ARPFLAG" = "0x0" ] && GUEST_IPADDR=""

					GUEST_HOST=""
					FOUND_IPADDR="$GUEST_IPADDR"

					if [ -z "$GUEST_IPADDR" ]
					then
						FOUND_IPADDR="$(grep -i "$GUEST_MACADDR" "$DNSMASQ_LEASES" | awk '{print $3}')"
						GUEST_IPADDR="$(grep -i "$GUEST_MACADDR" "$DNSMASQ_LEASES" | eval "$NOT_LANIP" | awk '{print $3}')"
					fi

					if [ -n "$GUEST_IPADDR" ]
					then
						GUEST_HOST="$(arp "$GUEST_IPADDR" | grep "$IFACE" | awk '{print $1}' | cut -f1 -d ".")"
						if [ -z "$GUEST_HOST" ] || [ "$GUEST_HOST" = "?" ]
						then
							GUEST_HOST="$(grep -i "$GUEST_MACADDR" "$DNSMASQ_LEASES" | eval "$NOT_LANIP" | awk '{print $4}')"
						fi

						if [ "$GUEST_HOST" = "*" ] || [ "$GUEST_HOST" = "?" ] || \
						   [ "$(printf "%s" "$GUEST_HOST" | wc -m)" -le 1 ]
						then
							GUEST_HOST="$(_NVRAM_Get_ custom_clientlist | grep -ioE "<.*>$GUEST_MACADDR" | awk -F ">" '{print $(NF-1)}' | tr -d '<')" #thanks Adamm00
						fi

						if [ -z "$GUEST_HOST" ] && [ -x /opt/bin/dig ]
						then
							GUEST_HOST="$(/opt/bin/dig +short +answer -x "$GUEST_IPADDR" '@'"$LAN_IPaddr" | cut -f1 -d'.')"
						fi
					elif [ -n "$FOUND_IPADDR" ]
					then
						GUEST_IPADDR="Not in Guest Net"
						GUEST_HOST="$(arp "$FOUND_IPADDR" | grep "$IFACE" | awk '{print $1}' | cut -f1 -d ".")"
						if [ -z "$GUEST_HOST" ] || [ "$GUEST_HOST" = "?" ]
						then
							GUEST_HOST="$(grep -i "$GUEST_MACADDR" "$DNSMASQ_LEASES" | awk '{print $4}')"
						fi

						if [ "$GUEST_HOST" = "*" ] || [ "$GUEST_HOST" = "?" ] || \
						   [ "$(printf "%s" "$GUEST_HOST" | wc -m)" -le 1 ]
						then
							GUEST_HOST="$(_NVRAM_Get_ custom_clientlist | grep -ioE "<.*>$GUEST_MACADDR" | awk -F ">" '{print $(NF-1)}' | tr -d '<')" #thanks Adamm00
						fi
					else
						GUEST_IPADDR="Unknown"
					fi

					if [ -z "$GUEST_HOST" ] || [ "$GUEST_HOST" = "*" ]
					then GUEST_HOST="Unknown" ; fi

					GUEST_HOST=$(echo "$GUEST_HOST" | tr -d '\n')
					GUEST_IPADDR=$(echo "$GUEST_IPADDR" | tr -d '\n')
					GUEST_MACADDR=$(echo "$GUEST_MACADDR" | tr -d '\n')
					GUEST_RSSI=$(wl -i "$IFACE" rssi "$GUEST_MACADDR" | tr -d '\n')

					GUEST_STAINFO=$(wl -i "$IFACE" sta_info "$GUEST_MACADDR")
					GUEST_TIMECONNECTED=$(echo "$GUEST_STAINFO" | grep "in network" | awk '{print $3}' | tr -d '\n')
					GUEST_TIMECONNECTED_PRINT=$(printf '%dh:%dm:%ds\n' $((GUEST_TIMECONNECTED/3600)) $((GUEST_TIMECONNECTED%3600/60)) $((GUEST_TIMECONNECTED%60)))

					GUEST_TX=$(echo "$GUEST_STAINFO" | grep "rate of last tx pkt" | awk '{print $6}' | tr -d '\n' | awk '{printf("%.0f", $1/1000);}')
					GUEST_RX=$(echo "$GUEST_STAINFO" | grep "rate of last rx pkt" | awk '{print $6}' | tr -d '\n' | awk '{printf("%.0f", $1/1000);}')

					GUEST_PHY=""
					if echo "$GUEST_STAINFO" | grep -q "HT caps"; then
						GUEST_PHY="n"
					elif echo "$GUEST_STAINFO" | grep -q "VHT caps"; then
						GUEST_PHY="ac"
					else
						GUEST_PHY="Unknown"
					fi

					"$NoARGs" && printf "%-32s%-18s%-20s%-15s%-15s%-11s%-6s${CLRct}\n" "$GUEST_HOST" "$GUEST_IPADDR" "$GUEST_MACADDR" "$GUEST_TIMECONNECTED_PRINT" "$GUEST_RX/$GUEST_TX Mbps" "$GUEST_RSSI dBm" "$GUEST_PHY"

					printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n" "$IFACE" "$GUEST_HOST" "$GUEST_IPADDR" "$GUEST_MACADDR" "$GUEST_TIMECONNECTED" "$GUEST_RX" "$GUEST_TX" "$GUEST_RSSI" "$GUEST_PHY" >> "$TMPSTATUSOUTPUTFILE"
				done
				unset IFS
			else
				"$NoARGs" && printf "   ${BOLD}${WARN}No clients connected${CLRct}\n"
				printf "%s,,NOCLIENTS,,,,,,\n" "$IFACE" >> "$TMPSTATUSOUTPUTFILE"
			fi
		fi
	done

	cp -fp "$TMPSTATUSOUTPUTFILE" "$STATUSOUTPUTFILE" 2>/dev/null
	rm -f "$TMPSTATUSOUTPUTFILE"
	"$NoARGs" && \
	{
	   printf "%114s\n\n" ' ' | tr ' ' '_'
	   printf "${BOLD}${PASS} Query complete, please see above for results${CLRct}\n\n"
	}
	#######################################################################################################
	renice 0 $$
}

##----------------------------------------##
## Modified by Martinski W. [2026-Aug-09] ##
##----------------------------------------##
Menu_Diagnostics()
{
    local DIAG_DPath="/tmp/${SCRIPT_NAME}Diag"
	local DIAG_FPath="/tmp/${SCRIPT_NAME}.tar.gz"

	printf "\n ${BOLD}This will collect the following information."
	printf "\n Files are encrypted with a unique random passphrase.${CLRct}"
	printf "\n ${WARN}[Make sure to copy and save the random passphrase]${CLRct}\n"
	printf "\n ${BOLD} - iptables rules${CLRct}"
	printf "\n ${BOLD} - ebtables rules${CLRct}"
	printf "\n ${BOLD} - %s${CLRct}" "$SCRIPT_CONF"
	printf "\n ${BOLD} - %s${CLRct}" "$DNSCONF"
	printf "\n ${BOLD} - /jffs/scripts/openvpn-event${CLRct}"
	printf "\n ${BOLD} - /jffs/scripts/firewall-start${CLRct}"
	printf "\n ${BOLD} - /jffs/scripts/services-start${CLRct}"
	printf "\n ${BOLD} - /jffs/scripts/service-event${CLRct}"
	printf "\n ${BOLD} - /jffs/scripts/service-event-end${CLRct}"
	printf "\n ${BOLD} - /jffs/scripts/dnsmasq.postconf${CLRct}\n\n"

	while true
	do
		printf "\n ${BOLD}Do you want to continue? (y/n)${CLRct}  "
		read -r confirm
		case "$confirm" in
			y|Y)
				break
			;;
			n|N)
				printf "\n ${MGNTct}User declined. Returning to main menu${CLRct}\n\n"
				return 1
			;;
			*)
				printf "\n Please choose a valid option (y/n)\n\n"
			;;
		esac
	done

	printf "\n\n ${BOLD}Generating %s diagnostics...${CLRct}\n" "$SCRIPT_NAME"

	mkdir -p "$DIAG_DPath"
	if [ ! -d "$DIAG_DPath" ]
	then
		printf "\n ${REDct}**ERROR**: Unable to create temporary directory.${CLRct}\n\n"
		return 1
	fi

	iptables-save > "$DIAG_DPath/iptables.txt"

	ebtables -L > "$DIAG_DPath/ebtables.txt"
	echo >> "$DIAG_DPath/ebtables.txt"
	ebtables -t broute -L >> "$DIAG_DPath/ebtables.txt"

	ip rule show > "$DIAG_DPath/iprule.txt"
	ip route show > "$DIAG_DPath/iproute.txt"
	ip route show table all | grep "table" | sed 's/.*\(table.*\)/\1/g' | awk '{print $2}' | sort | uniq | grep ovpn > "$DIAG_DPath/routetablelist.txt"

	while IFS='' read -r line || [ -n "$line" ]
	do
		ip route show table "$line" > "$DIAG_DPath/iproute_$line.txt"
	done < "$DIAG_DPath/routetablelist.txt"

	ifconfig -a > "$DIAG_DPath/ifconfig.txt"

	cp "$SCRIPT_CONF" "$DIAG_DPath/${SCRIPT_NAME}.conf"
	cp "$DNSCONF" "$DIAG_DPath/${SCRIPT_NAME}.dnsmasq"

	cp /jffs/scripts/openvpn-event "$DIAG_DPath/openvpn-event"
	cp /jffs/scripts/firewall-start "$DIAG_DPath/firewall-start"
	cp /jffs/scripts/services-start "$DIAG_DPath/services-start"
	cp /jffs/scripts/service-event "$DIAG_DPath/service-event"
	cp /jffs/scripts/service-event-end "$DIAG_DPath/service-event-end"
	cp /jffs/scripts/dnsmasq.postconf "$DIAG_DPath/dnsmasq.postconf"

	SEC="$(Generate_Random_String 32)"
	tar -czf "$DIAG_FPath" -C "$DIAG_DPath" .
	/usr/sbin/openssl enc -aes-256-cbc -pbkdf2 -k "$SEC" -e -in "$DIAG_FPath" -out "${DIAG_FPath}.enc"

	printf "\n ${BOLD}Diagnostics saved to ${GRNct}${DIAG_FPath}.enc${CLRct}"
	printf " with passphrase ${GRNct}${SEC}${CLRct}"
	printf "\n ${MGNTct}[Make sure to copy and save the random passphrase]${CLRct}\n\n"

	rm -f "$DIAG_FPath" 2>/dev/null
	rm -fr "$DIAG_DPath" 2>/dev/null
	SEC=""
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-18] ##
##----------------------------------------##
Menu_Uninstall()
{
	IFACE_WAN="$(_NVRAM_Get_WAN_IFace_)"

	Print_Output true "Removing $SCRIPT_NAME..." "$PASS"

	NetworkMap_WebUI stop 2>/dev/null
	Auto_NetworkMapServiceEventEnd delete 2>/dev/null
	Auto_Startup delete 2>/dev/null
	Auto_Cron delete 2>/dev/null
	Auto_DNSMASQ delete 2>/dev/null
	Auto_ServiceEvent delete 2>/dev/null
	Auto_ServiceStart delete 2>/dev/null
	Auto_OpenVPNEvent delete 2>/dev/null
	Avahi_Conf delete 2>/dev/null
	if [ "$(_FWVersionStrToNum_ "$fwInstalledBranchVer")" -lt "$(_FWVersionStrToNum_ 3004.386.3)" ]
	then
		Routing_NVRAM deleteall 2>/dev/null
	else
		Routing_VPNDirector deleteall 2>/dev/null
	fi
	Firewall_NAT deleteall 2>/dev/null
	Routing_RPDB delete 2>/dev/null
	Firewall_Chains deleteall 2>/dev/null
	Firewall_NVRAM disableall "$IFACE" 2>/dev/null
	Iface_Manage deleteall 2>/dev/null
	DHCP_Conf deleteall 2>/dev/null

	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"
	Get_WebUI_Page "$SCRIPT_DIR/YazFi_www.asp"
	if [ -n "$MyWebPage" ] && \
	   [ "$MyWebPage" != "NONE" ] && \
	   [ -f "$TEMP_MENU_TREE" ]
	then
		sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"
		rm -f "$SCRIPT_WEBPAGE_DIR/$MyWebPage"
		rm -f "$SCRIPT_WEBPAGE_DIR/$(echo "$MyWebPage" | cut -f1 -d'.').title"
		umount /www/require/modules/menuTree.js
		mount -o bind "$TEMP_MENU_TREE" /www/require/modules/menuTree.js
	fi
	flock -u "$FD"
	rm -f "$SCRIPT_DIR/YazFi_www.asp"

	while true
	do
		printf "\n${BOLD}Do you want to delete %s configuration file(s)? (y/n)${CLRct}  " "$SCRIPT_NAME"
		read -r confirm
		case "$confirm" in
			y|Y)
				rm -fr "$SCRIPT_DIR"
				break
			;;
			*)
				break
			;;
		esac
	done

	SETTINGSFILE="${JFFS_ADDONS}/custom_settings.txt"
	sed -i '/yazfi_version_local/d' "$SETTINGSFILE"
	sed -i '/yazfi_version_server/d' "$SETTINGSFILE"
	Shortcut_Script delete
	rm -f "$SCRIPT_FPATH"
	Clear_Lock
	Print_Output true "Restarting firewall to complete uninstall" "$PASS"
	service restart_dnsmasq >/dev/null 2>&1
	service restart_firewall >/dev/null 2>&1
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-17] ##
##----------------------------------------##
Show_About()
{
	printf "About ${MGNTct}${SCRIPT_VERS_INFO}${CLRct}\n"
	cat <<EOF
  $SCRIPT_NAME is a feature expansion of Guest WiFi networks on
AsusWRT-Merlin, including SSID -> VPN, separate subnets per guest
network, pinhole access to LAN resources (e.g. DNS) and more!

License
  $SCRIPT_NAME is free to use under the GNU General Public License
  version 3 (GPL-3.0) https://opensource.org/licenses/GPL-3.0

Help & Support
  https://www.snbforums.com/forums/asuswrt-merlin-addons.60/?prefix_id=13

Source code
  https://github.com/AMTM-OSR/$SCRIPT_NAME
EOF
	printf "\n"
}

### function based on @dave14305's FlexQoS show_help function ###
##------------------------------------------##
## Modified by ExtremeFiretop [2026-Jul-02] ##
##------------------------------------------##
Show_Help()
{
	printf "HELP ${MGNTct}${SCRIPT_VERS_INFO}${CLRct}\n"
	cat <<EOF
Available commands:
  $SCRIPT_NAME about            explains functionality
  $SCRIPT_NAME update           checks for updates
  $SCRIPT_NAME forceupdate      updates to latest version (force update)
  $SCRIPT_NAME startup          runs startup actions such as mount WebUI tab
  $SCRIPT_NAME install          installs script
  $SCRIPT_NAME uninstall        uninstalls script
  $SCRIPT_NAME runnow           apply $SCRIPT_NAME configuration
  $SCRIPT_NAME check            check if $SCRIPT_NAME configuration is still in effect and re-apply if not
  $SCRIPT_NAME bounceclients    restart guest network radios
  $SCRIPT_NAME status           print information about clients connected to $SCRIPT_NAME guest networks
  $SCRIPT_NAME networkmap start enable/remount native Network Map integration
  $SCRIPT_NAME check            check if $SCRIPT_NAME configuration is still in effect and re-apply if not
  $SCRIPT_NAME userscripts      run userscripts (if any have been created)
  $SCRIPT_NAME rejectlogging    toggle whether rejected packets are logged to syslog
  $SCRIPT_NAME develop          switch to development branch version
  $SCRIPT_NAME stable           switch to stable/production branch version
EOF
	printf "\n"
}

##----------------------------------------##
## Modified by Martinski W. [2023-Dec-22] ##
##----------------------------------------##
# Make the one call needed to load module #
modprobe xt_comment

if [ "$SCRIPT_BRANCH" = "master" ]
then SCRIPT_VERS_INFO=""
else SCRIPT_VERS_INFO="[$versionDev_TAG]"
fi

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
if [ $# -eq 0 ] || [ -z "$1" ]
then
	if ! _Firmware_Support_Check_ || \
	   ! _Firmware_Version_WebUI_
	then
		if [ -d "$SCRIPT_DIR" ]
		then
		    printf "${SETTING}To uninstall use this command:  ${CLRct}"
		    printf "${MGNTct}$SCRIPT_FPATH uninstall${CLRct}\n\n"
		fi
		PressEnter
		printf "\n${ERR}Exiting...${CLRct}\n\n"
		Clear_Lock
		exit 1
	fi

	Create_Dirs
	Create_Symlinks
	Conf_Exists
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_DNSMASQ create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Auto_NetworkMapServiceEventEnd create 2>/dev/null
	Auto_ServiceStart create 2>/dev/null
	Auto_OpenVPNEvent create 2>/dev/null
	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Shortcut_Script create
	_CheckFor_WebGUI_Page_
	_CheckFor_NetworkMap_SourceJS_
	NetworkMap_Apply
	MainMenu
	exit 0
fi

##----------------------------------------##
## Modified by Martinski W. [2026-Sep-05] ##
##----------------------------------------##
if [ "$1" != "install" ]   && \
   [ "$1" != "uninstall" ] && \
   { ! _Firmware_Support_Check_ || \
     ! _Firmware_Version_WebUI_
   }
then
	printf "${ERR}Exiting...${CLRct}\n"
	exit 1
fi

case "$1" in
	install)
		Menu_Install
		exit 0
	;;
	startup)
		Menu_Startup
		exit 0
	;;
	uninstall)
		Menu_Uninstall
		exit 0
	;;
	runnow)
		Check_Lock
		Print_Output true "Firewall restarted - sleeping 10s before running $SCRIPT_NAME" "$PASS"
		sleep 10
		Config_Networks
		Clear_Lock
		exit 0
	;;
	check)
		if [ "$(grep -c "NextDNS" /jffs/scripts/dnsmasq.postconf)" -gt 0 ]
		then
			if [ "$(grep -c "exit 0" /jffs/scripts/dnsmasq.postconf)" -gt 0 ]
			then
				sed -i '/exit 0/d' /jffs/scripts/dnsmasq.postconf
				service restart_dnsmasq
			fi
		fi
		if ! Conf_Exists; then
			exit 1
		fi
		if ! Conf_Validate; then
			exit 1
		fi

		##----------------------------------------##
		## Modified by Martinski W. [2024-Jan-06] ##
		##----------------------------------------##
		if echo "$IFACELIST" | grep -qE "wl[0-3][.][1-3]" && \
		   { ! iptables -t nat -nL | grep -q "YazFi"    || \
		     ! iptables -t nat -nL | grep -wq "YazFi"   || \
		     ! iptables -t filter -nL | grep -q "YazFi" || \
		     ! iptables -t filter -nL | grep -wq "YazFi"
		   }
		then
			Check_Lock
			Print_Output true "$SCRIPT_NAME firewall rules were not detected during persistence check, re-applying rules" "$ERR"
			Config_Networks
			Clear_Lock
			exit 0
		fi

		. $SCRIPT_CONF
		WIRELESSRESTART="false"
		for IFACE in $IFACELIST
		do
			if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ENABLED")" = "true" ] && \
			   Validate_IFACE_Enabled "$IFACE" silent
			then
				if [ "$(_NVRAM_Get_ "${IFACE}_lanaccess")" != "on" ]
				then
					nvram set "$IFACE"_lanaccess=on
					WIRELESSRESTART="true"
				fi

				##----------------------------------------##
				## Modified by Martinski W. [2023-Dec-28] ##
				##----------------------------------------##
				if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ONEWAYTOGUEST")" = "true" ] || \
				   [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_TWOWAYTOGUEST")" = "true" ]
				then  # Disable ISOLATION #
					if [ "$(_NVRAM_Get_ "${IFACE}_ap_isolate")" != "0" ]
					then
						nvram set "$IFACE"_ap_isolate=0
						WIRELESSRESTART="true"
					fi
				fi
			fi
		done

		if [ "$WIRELESSRESTART" = "true" ]
		then
			nvram commit
			Print_Output true "$SCRIPT_NAME is restarting wireless services now." "$WARN"
			service restart_wireless >/dev/null 2>&1
		fi
		exit 0
	;;
	bounceclients)
		. "$SCRIPT_CONF"
		Conf_Validate
		Iface_BounceClients
		exit 0;
	;;
	service_event)
		if [ "$2" = "restart" ] && [ "$3" = "wireless" ]
		then
			Check_Lock
			Print_Output true "Wireless restarted - sleeping 30s before running $SCRIPT_NAME" "$PASS"
			sleep 30
			Config_Networks
			Clear_Lock
		elif [ "$2" = "start" ] && [ "$3" = "$SCRIPT_NAME" ]
		then
			Conf_FromSettings
			Print_Output true "WebUI config updated - running $SCRIPT_NAME" "$PASS"
			Check_Lock
			Config_Networks
			Clear_Lock
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}checkupdate" ]
		then
			Update_Check
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}doupdate" ]
		then
			Update_Version force unattended
			exit 0
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}connectedclients" ]
		then
			sleep 2
			if ! _ConnectedClientsCheckRunning_
			then Menu_Status outputtofile
			fi
		fi
		exit 0
	;;
	openvpn)
		if echo "$2" | grep -q tun1 && [ "$3" = "route-up" ]
		then
			Print_Output true "VPN tunnel route just came up, running YazFi to fix RPDB routing" "$PASS"
			sleep 5

			if ! Conf_Exists; then
				return 1
			fi
			if ! Conf_Validate; then
				return 1
			fi
			. $SCRIPT_CONF

			for IFACE in $IFACELIST
			do
				if [ "$(eval echo '$'"$(Get_Iface_Var "$IFACE")_ENABLED")" = "true" ] && \
				   Validate_IFACE_Enabled "$IFACE" silent
				then
					Routing_RPDB create "$IFACE" 2>/dev/null
				fi
			done
		fi
	;;
	networkmap)
		case "$2" in
			start|remount|stop)
				NetworkMap_WebUI "$2" ;;
			daemon)
				NetworkMap_Daemon run ;;
			refresh)
				NetworkMap_Generate_JSON ;;
			enable)
				NetworkMap_Set_Enabled true && NetworkMap_WebUI start ;;
			disable)
				NetworkMap_Set_Enabled false && NetworkMap_WebUI stop ;;
			status)
				NetworkMap_Status ;;
			*) echo "Usage: $SCRIPT_NAME networkmap {enable|disable|start|remount|stop|refresh|status}" >&2
			   exit 1 ;;
		esac
		exit "$?"
	;;
	status)
		Menu_Status
		exit 0
	;;
	statustofile)
		Menu_Status outputtofile
		exit 0
	;;
	userscripts)
		Execute_UserScripts
		exit 0
	;;
	rejectlogging)
		if [ -f "$SCRIPT_DIR/.rejectlogging" ]; then
			rm -f "$SCRIPT_DIR/.rejectlogging"
		else
			touch "$SCRIPT_DIR/.rejectlogging"
		fi
		service restart_firewall >/dev/null 2>&1
		exit 0
	;;
	update)
		Update_Version
		exit 0
	;;
	forceupdate)
		Update_Version force unattended
		exit 0
	;;
	amtmupdate)
		shift
		ScriptUpdateFromAMTM "$@"
		exit "$?"
	;;
	checkupdate)
		Update_Check
		exit 0
	;;
	setversion)
		Set_Version_Custom_Settings local "$SCRIPT_VERSION"
		Set_Version_Custom_Settings server "$SCRIPT_VERSION"
		Create_Dirs
		Create_Symlinks
		Auto_Startup create 2>/dev/null
		Auto_Cron create 2>/dev/null
		Auto_DNSMASQ create 2>/dev/null
		Auto_ServiceEvent create 2>/dev/null
		Auto_NetworkMapServiceEventEnd create 2>/dev/null
		Auto_ServiceStart create 2>/dev/null
		Auto_OpenVPNEvent create 2>/dev/null
		Shortcut_Script create
		NetworkMap_Apply
		exit 0
	;;
	postupdate)
		Create_Dirs
		Create_Symlinks
		Auto_Startup create 2>/dev/null
		Auto_Cron create 2>/dev/null
		Auto_DNSMASQ create 2>/dev/null
		Auto_ServiceEvent create 2>/dev/null
		Auto_NetworkMapServiceEventEnd create 2>/dev/null
		Auto_ServiceStart create 2>/dev/null
		Auto_OpenVPNEvent create 2>/dev/null
		Shortcut_Script create
		Update_File YazFi_networkmap.js
		NetworkMap_Apply
		exit 0
	;;
	develop)
		SCRIPT_BRANCH="develop"
		SCRIPT_REPO="https://raw.githubusercontent.com/AMTM-OSR/$SCRIPT_NAME/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	stable)
		SCRIPT_BRANCH="master"
		SCRIPT_REPO="https://raw.githubusercontent.com/AMTM-OSR/$SCRIPT_NAME/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	about)
		ScriptHeader
		Show_About
		exit 0
	;;
	help)
		ScriptHeader
		Show_Help
		exit 0
	;;
	*)
		ScriptHeader
		Print_Output false "Parameter [$*] is NOT recognised." "$ERR"
		Print_Output false "For a list of available commands run: $SCRIPT_NAME help" "$SETTING"
		exit 1
	;;
esac
