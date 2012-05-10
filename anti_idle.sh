#!/bin/bash

# #############################################################################
# Anti Idle script - V 1.2 - 11/11/21
# By Adrien Mahieux <adrien.mahieux@gmail.com>
# #############################################################################
# 
# Requirement: xdotool http://www.semicomplete.com/projects/xdotool
# 
# Other tools with less / other features :
# xte        Control X from cmd. (pkg xautomation)
# xwininfo   Get X Windows info
# xidle      Monitor inactivity in X and run specified program
#
# #############################################################################


BIN_XDO=/usr/bin/xdotool
BIN_AWK=/usr/bin/awk
BIN_PS=/bin/ps
BIN_XIDLE=/usr/bin/xidle
BIN_READLINK=/usr/bin/readlink
BIN_REALPATH=/usr/bin/realpath
BIN_MYSELF="$($BIN_READLINK $0 || $BIN_REALPATH $0)"


VAL_SLEEP=60
VAL_STEP=10
VAL_VERB=0
VAL_DAEMON=0
VAL_IDLE=300

function window_getid {

	WNDIDS=""

	unset OPTIND
	unset OPTARG
	while getopts ":p:P:n:i:" opt $@; do
		case $opt in
			# By ID
			i)
				WNDIDS="$WNDIDS $OPTARG"
#				echo "Parsed $opt = $OPTARG" >> /dev/stderr
				;;
			# By process
			p)
				WNDIDS="$WNDIDS $($BIN_XDO search --class $OPTARG)"
#				echo "Parsed $opt = $OPTARG" >> /dev/stderr
				;;
			# By PID
			P)
				_WNDCLS="$($BIN_PS h -o comm -p $OPTARG)"
				WNDIDS="$WNDIDS $($BIN_XDO)"
#				echo "Parsed $opt = $OPTARG" >> /dev/stderr
				;;
			# By name
			n)
				WNDIDS="$WNDIDS $($BIN_XDO search --name "$OPTARG")"
#				echo "Parsed $opt = $OPTARG" >> /dev/stderr
				;;
			\?)
				echo "Wrong window_getids arg : $OPTARG"
#				echo "Parsed $opt = $OPTARG" >> /dev/stderr
				exit 2
				;;
		esac
	done
#	echo "Final : $WNDIDS" >> /dev/stderr
	echo $WNDIDS
	[ -n "$WNDIDS" ] && return 0
	return 1
}


function mouse_move {
	$BIN_XDO mousemove_relative -- -1 0
	$BIN_XDO mousemove_relative --  1 0

	return $?
}

function mouse_checkpos {
	[ -z "$1" ] && return 1
	WND_ID="$1"
	eval $($BIN_XDO getmouselocation --shell 2>/dev/null)
	# Now we have vars X,Y,SCREEN,WINDOW
	
	[ "$WND_ID" != "$WINDOW" ] && {
		return 1
	}
	return 0
}

function mouse_hoverwindow {
	[ -z "$1" ] && return 1

	WND_ID=$1
	# And the info
	eval $($BIN_XDO getwindowgeometry --shell $WND_ID)
	# Now we have vars X,Y,SCREEN,WINDOW
	WND_X=$X
	WND_Y=$Y
	WND_S=$SCREEN
	WND_W=$WIDTH
	WND_H=$HEIGHT
	
	eval $($BIN_XDO getmouselocation --shell 2>/dev/null)
	MOU_X=$X
	MOU_Y=$Y
	
	
	# Check if we are on the good virtual desktop
	DESK_WND=$($BIN_XDO get_desktop_for_window $WND_ID)
	DESK_CUR=$($BIN_XDO get_desktop)
	
	[ "$DESK_WND" != "$DESK_CUR" ] && {
		$BIN_XDO set_desktop $DESK_WND
	}
	
	# Move the mouse to hover the window
	$BIN_XDO mousemove $X+1 $Y+1
	
	# If the window if masked by another, try to move the mouse
	CNT_X=0
	CNT_Y=0
	MAX_X=$(($WND_X + $WND_W))
	MAX_Y=$(($WND_Y + $WND_H))
	while [ "$(mouse_checkpos $WND_ID ; echo $?)" != "0" ]; do
		NEW_X=$(($WND_X+ $CNT_X*$VAL_STEP))
		NEW_Y=$(($WND_Y+ $CNT_Y*$VAL_STEP))

		$BIN_XDO mousemove $NEW_X $NEW_Y
		
		[ $NEW_X -gt $MAX_X ] && { 
			CNT_X=0
			CNT_Y=$(($CNT_Y+1)) 
		}
		[ $NEW_Y -gt $MAX_Y ] && {
			return 1
		}

		CNT_X=$(($CNT_X+$VAL_STEP))
	done
	
	# Set back to the old position
	[ "$DESK_WND" != "$DESK_CUR" ] && {
		$BIN_XDO set_desktop $DESK_CUR
	}
	$BIN_XDO mousemove $MOU_X $MOU_Y

	return 0
}



function help {
	echo "Usage"
	echo "$0  <-p process | -P PID | -n name | -i WND_ID | -w>"
	echo "             [-d [idleTime]] [-s Sleep] [-S Step]"
	echo ""
	echo "Select the process(es) to watch by specifiying :"
	echo "  -p         Process name"
	echo "  -P         PID"
	echo "  -n         Display name"
	echo "  -i         X-Window ID"
	echo "  -w         Wizzard mode. Select with the mouse the window"
	echo ""
	echo "  -d [idle]  Daemonize after Xorg being idle for [$VAL_IDLE] seconds"
	[ -x "$BIN_XIDLE" ] && {
	echo "             Feature available: xidle = $BIN_XIDLE" 
	} || {
	echo "             Feature disabled. unable to find \"xidle\" command"
	}
	echo ""
	echo "  -s         Time to sleep between checks. Value: $VAL_SLEEP s"
	echo "  -S         Step used when hunting the window. Value: $VAL_STEP px"
	echo ""
}


WATCH_ARGS=""
# Args parsing
while getopts ":wi:p:P:n:s:S:d:vh" opt; do
	case $opt in
		# Wizzard
		w) 		WATCH_ARGS="$WATCH_ARGS -i $($BIN_XDO selectwindow 2>/dev/null)" 	;;

		# By process, PID, name, ID
		p|P|n|i)WATCH_ARGS="$WATCH_ARGS -$opt $OPTARG"	;;

		
		# Set the sleep
		s)		VAL_SLEEP=$OPTARG;;
		# Set the step
		S)		VAL_STEP=$OPTARG;;
		# Set the verbosity
		v)		VAL_VERB=$((VAL_VERB+1)) ;;
		# Should daemonize
		d)		VAL_DAEMON=$OPTARG 	;;
		h)		help ; exit 0 ;;
		\?)		echo "Unknown option -$OPTARG" ; exit 1 ;;

		# Args with default value
		:)
			case $OPTARG in
				d) VAL_DAEMON=$VAL_IDLE	;;
				*) echo "No default value for $OPTARG" ;;
			esac
			;;
	esac
done

OTHER_ARGS="-s $VAL_SLEEP -S $VAL_STEP"

# TODO: Add the daemonizing features
[ "$VAL_DAEMON" != "0" ] && {
	$BIN_XIDLE -timeout $VAL_DAEMON -program "$BIN_MYSELF $OTHER_ARGS $WATCH_ARGS" &
	echo $!
	exit 0;
}


[ -z "$WATCH_ARGS" ] && {
	echo "No process to watch specified."
	exit 1
}


while [ 1 ]; do 
	# If process(es) running
	_WNDIDS="$(window_getid $WATCH_ARGS)"
	[ $? -eq 0 ] && {

		# Found IDs, for each of them
		for ID in $_WNDIDS; do 

			echo "Waking up window $ID"
			# Are we on the good window
			mouse_checkpos $ID || {
				# Can we hover the window
				mouse_hoverwindow $ID || {
					# If no, try to activate the window, firstscreen
					$BIN_XDO windowactivate $ID
					mouse_hoverwindow $ID
				}
			}
			mouse_move
		done
	}
	sleep $VAL_SLEEP
done

