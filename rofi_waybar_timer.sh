#!/usr/bin/env bash

# allows optional decimal, m/min units, & whitespace
regex='^[[:space:]]*([0-9]*\.?[0-9]+)([[:space:]]*(min|m))?[[:space:]]*$'

TIMER_FILE=/tmp/waybar_timer
TIMER_PAUSED=/tmp/timer_paused

cleanup_timer_file() {
	# how long before the timer dissappears from waybar
	sleep 10 && rm -f "$TIMER_FILE"
}

# Stop other instances of this script while keeping the current process alive.
kill_running_timers() {
	local self_pid
	self_pid="${BASHPID:-$$}"
	OTHER_PIDS=$(pgrep -f "$(basename "$0")" | grep -v -x "$self_pid" || true)
	if [ -n "$OTHER_PIDS" ]; then
		echo "$OTHER_PIDS" | xargs kill
	fi
}

if [[ $1 == "waybar_fetch" ]]; then
	[[ ! -f $TIMER_FILE ]] && echo '{"text": "", "class": "stopped"}' && exit 0

	content=$(<"$TIMER_FILE")
	status="active"
	[[ -f "$TIMER_PAUSED" ]] && status="paused"
	printf '{"text": "%s", "alt": "%s", "class": "%s"}\n' "$content" "$status" "$status"

	exit 0
fi

if [[ $1 == "waybar_toggle" && -f $TIMER_FILE ]]; then
	if [[ -f $TIMER_PAUSED ]]; then
		rm "$TIMER_PAUSED"
	else
		touch "$TIMER_PAUSED"
	fi
	exit 0
fi

start_timer() {
	local duration_sec current_time end_time
	duration_sec=$(awk "BEGIN {print int($1 * 60)}")
	current_time=$(date +%s)
	end_time=$(( current_time + duration_sec ))

	rm -f $TIMER_PAUSED
	touch $TIMER_FILE

	while [[ -f $TIMER_FILE ]]; do
		local current_time remaining_sec formatted_time
		current_time=$(date +%s)
		remaining_sec=$(( end_time - current_time ))

		# Add a second to paused time each second to maintain duration
		if [[ -f "$TIMER_PAUSED" ]]; then
			((end_time++))
		elif (( remaining_sec <= 0 )); then
			break
		fi

		# format MM:SS
		formatted_time=$(printf "%02d:%02d" $((remaining_sec/60)) $((remaining_sec%60)))
		echo "$formatted_time" > $TIMER_FILE
		sleep 1
	done

	if [[ -f $TIMER_FILE ]]; then
		echo "Done" > $TIMER_FILE
		handle_timer_finished &
		notify-send "Time is up!" "Go do the thing you were supposed to do." -u critical
	fi
}

handle_timer_finished() {
	local done_popup minutes

	done_popup=$(rofi -dmenu -i -no-fixed-num-lines \
		-theme-str 'window {width: 20%; }' \
		-p "Timer Finished!" <<-EOF
			Done
			Snooze 5 min
		EOF
	)

	case "$done_popup" in
		"Snooze 5 min")
			start_timer 5
			return
			;;
		"Done"|"")
			cleanup_timer_file
			return
			;;
	esac
	if [[ $done_popup =~ $regex ]]; then
		minutes=${BASH_REMATCH[1]}
		start_timer "$minutes" &
		notify-send "Timer Snoozed" "$minutes min" -u normal
		return
	else
		cleanup_timer_file && notify-send "Input Error" -u critical
	fi
}

pause_option="Pause"
[[ -f $TIMER_PAUSED ]] && pause_option="Resume" || pause_option="Pause"

# NOTE: will auto select from the options if part of the input matches string
input=$(rofi -dmenu -i -no-fixed-num-lines \
  -theme-str 'window {width: 20%; }' \
  -p "Timer:" <<-EOF
		25 min
		5 min
		$pause_option
		Cancel Timer
	EOF
)

case $input in
	"$pause_option")
		if [[ -f $TIMER_PAUSED ]]; then
			rm $TIMER_PAUSED && notify-send "Timer Resumed" -u normal
		else
			touch $TIMER_PAUSED && notify-send "Timer Paused" -u normal
		fi
		exit 0
		;;

	"Cancel Timer")
		rm $TIMER_FILE && notify-send "Timer Cancelled" -u normal
		exit 0
		;;

	"")
		exit 0
		;;
esac

if [[ $input =~ $regex ]]; then
	minutes=${BASH_REMATCH[1]}
	kill_running_timers
	start_timer "$minutes" &
	notify-send "Timer Started" "$minutes min" -u normal
	exit 0
else
	notify-send "Input Error" -u critical
fi
