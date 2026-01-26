#!/usr/bin/env bash

timer_file=/tmp/waybar_timer
timer_paused=/tmp/timer_paused

# waybar get timer
if [[ $1 == "get" ]]; then
	if [[ -f $timer_file ]]; then
		content=$(cat $timer_file)
		# printf json for waybar
		if [[ -f "$timer_paused" ]]; then
			printf '{"text": "%s", "alt": "paused", "class": "paused"}\n' "$content"
		else
			printf '{"text": "%s", "alt": "active", "class": "active"}\n' "$content"
		fi
	else
		echo '{"text": "", "class": "stopped"}'
	fi
	exit 0
fi

# waybar pause/resume on-click
if [[ $1 == "toggle" ]]; then
	if [[ -f $timer_file ]]; then
		if [[ -f $timer_paused ]]; then
			rm "$timer_paused"
		else
			touch "$timer_paused"
		fi
	fi
	exit 0
fi

start_timer() {
	local duration_sec current_time end_time
	duration_sec=$(awk "BEGIN {print int($1 * 60)}")
	current_time=$(date +%s)
	end_time=$(( current_time + duration_sec ))

	rm -f $timer_paused
	touch $timer_file

	while [[ -f $timer_file ]]; do
		local current_time remaining_sec formatted_time
		current_time=$(date +%s)
		remaining_sec=$(( end_time - current_time ))

		if [[ -f $timer_paused ]]; then
			# Add a second to paused time each second to maintain duration
			((end_time++))
		else
			if [ $remaining_sec -le 0 ]; then
				break
			fi
		fi

		# format MM:SS
		formatted_time=$(printf "%02d:%02d" $((remaining_sec/60)) $((remaining_sec%60)))
		echo $formatted_time > $timer_file
		sleep 1
	done

	if [[ -f $timer_file ]]; then
		echo "Done" > $timer_file
		notify-send "Time is up!" "Go do the thing you were supposed to do." -i alarm-clock -u critical

		done_popup=$(rofi -dmenu -p "Timer Finished!" <<-EOF
			Done
			Snooze 5 min
		EOF
		)

		case $done_popup in
			"Snooze 5 min")
				start_timer 5
				;;

			"Done")
				sleep 5
				rm $timer_file
				;;

			"")
				sleep 5
				rm $timer_file
				;;

			*)
				if [[ $done_popup =~ ^([0-9]*\.?[0-9]+)([[:space:]?]*min|m)?$ ]]; then
					# Find and kill any existing timer processes so they stop writing to the file
					OTHER_PIDS=$(pgrep -f "$(basename "$0")" | grep -v "^$$$")
					if [ -n "$OTHER_PIDS" ]; then
						echo "$OTHER_PIDS" | xargs kill
					fi

					minutes=${BASH_REMATCH[1]}
					notify-send "Timer Started" "$minutes min" -i alarm-clock -u normal
					start_timer $minutes
					exit 0
				else
					notify-send "Input Error" -u critical
					sleep 5
					rm $timer_file
					exit 1
				fi
				;;
		esac
	fi
}

pause_option="Pause"
if [[ -f $timer_paused ]]; then
	pause_option="Resume"
else
	pause_option="Pause"
fi

# NOTE: Auto selects from results if part of input matches string, need to type m after for custom time
input=$(rofi -dmenu -p "Set Timer:" <<-EOF
	25 min
	5 min
	$pause_option
	Cancel Timer
EOF
)

case $input in
	$pause_option)
		if [[ -f $timer_paused ]]; then
			rm $timer_paused
			notify-send "Timer Resumed" -i alarm-clock -u normal
		else
			touch $timer_paused
			notify-send "Timer Paused" -i alarm-clock -u normal
		fi
		exit 0
		;;

	"Cancel Timer")
		rm $timer_file
		notify-send "Timer Cancelled" -i alarm-clock -u normal
		exit 0
		;;

	"")
		exit 0
		;;

	*)
		if [[ $input =~ ^([0-9]*\.?[0-9]+)([[:space:]?]*min|m)?$ ]]; then
			# Find and kill any existing timer processes so they stop writing to the file
			OTHER_PIDS=$(pgrep -f "$(basename "$0")" | grep -v "^$$$")
			if [ -n "$OTHER_PIDS" ]; then
				echo "$OTHER_PIDS" | xargs kill
			fi

			minutes=${BASH_REMATCH[1]}
			notify-send "Timer Started" "$minutes min" -i alarm-clock -u normal
			start_timer $minutes
			exit 0
		else
			notify-send "Input Error" -u critical
			exit 1
		fi
esac
