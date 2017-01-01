#!/usr/bin/env bash

# please do not alter below comment with double hash. This is for easyoptions.sh script to automatically parse & build global state
## Flea-circus: serial_flea.sh 
## Licensed under BSD
##
## This program is part of flea-circus. It executes provided list of commands serially and if failed reattempts. Usage:
##
##     @script.name [option] COMMANDS...
## 
## Where COMMANDS should be provided as following: processA='echo 1' processB='hostname' source
## in this example first will be execute command 'echo 1' and identified as processA...
##
## Options:
##     -h, --help              	     Print help about usage of this script
##     -d, --debug  				 Enable verbose mode (sets log level to DEBUG) if not enabled level set to INFO
##         --max-retries=VALUE	     Maximum number of reattempts for commands that fail
##         --log-dir=VALUE	 	     Directory where logs from invoked commands will be stored, should be writable by script owner
##         --log-prefix=VALUE	     Prefix that will be used to prepend all logs with, should contain only characters
##		   --sec-between-cmd=VALUE   Number of seconds to sleep between starting next command (default 0)
##		   --sec-between-retry=VALUE Number of seconds to sleep between retrying failed command (default 0)




#	execute

# ==========================================================
#	libraries

source log.sh || exit 1
source easyoptions.sh || exit 1

# ==========================================================
# global variables declaration & configuration

declare -a COMMANDS
# holds durations of all executed commands in seconds, order same as COMMANDS
declare -a COMMAND_DURATION_SEC
# exit statuses
declare -a COMMAND_EXIT_STATUSES
# number of retries for each command
declare -a COMMAND_RETRIES
# log name for each command
declare -a COMMAND_LOGS

# temporal global array to return value from split_command
declare -A TEMP_COMMAND_ARRAY
declare -i -r MAX_RETRIES=$max_retries
declare -r LOG_DIR=$log_dir
declare -r LOG_PREFIX=$log_prefix
declare -r -i SECONDS_BETWEEN_COMMANDS=${sec_between_cmd:=0}
declare -r -i SECONDS_BETWEEN_RETRIES=${sec_between_retry:=0}
declare -i NUMBER_OF_COMMAND_FAILURES=0

#	set default logging level to DEBUG for --debug, INFO otherwise
if [ -z "$debug"  ]; then
	LS_LEVEL=LS_INFO_LEVEL 
else
	LS_LEVEL=LS_DEBUG_LEVEL 	
fi
# ==========================================================
#	functions
die () {
    LSERROR "$@"
    exit 1
}

# execute command redirecting output to specified log file
# if fails return
# Arguments:
# $1 - full command with arguments 'echo 1'
# $2 - index of the command (0 starting) so that information about logs will be stored in COMMAND_LOGS[$2]
execute_cmd(){

	local full_command=$1
	local command_index=$2
	LSDEBUG "execute_cmd($full_command, $command_index)..."
	split_command "$full_command" 
	local -r command_label=${TEMP_COMMAND_ARRAY[label]}	
	local -r command=${TEMP_COMMAND_ARRAY[cmd]}
	LSDEBUG " command_label: $command_label, command: $command"
	local -r cmd_stamp=$(date +'%Y%m%d_%H%M%S%N')
	local -r cmd_log="$LOG_DIR/${LOG_PREFIX}_${command_label}_${cmd_stamp}.log"
	
	COMMAND_LOGS[$command_index]=$cmd_log
	
	LSDEBUG "Will execute $command > $cmd_log (stdout & stderr)"
	eval "$command &> $cmd_log"	# result of last command in bash is automatically returned from this function to calling context(stored in $?)
}

# execute all commands. Reattempt on failure.
execute_all_commands(){
	
	LSINFO "Attempt to execute $number_all_jobs commands serially..."
	
	local -i -r number_all_jobs=${#COMMANDS[@]} 
	local -i processed_commands=1		
	local -i cmd_index
	local -i execution_status	
	local -i seconds_since_launch	
	local duration_message
	
	for full_command in "${COMMANDS[@]}"; do
	
		local -i execution_attempt_no=1
				 
		while [ 1 ]
		do
			LSINFO " starting [job $processed_commands from $number_all_jobs, attempt: $execution_attempt_no] $full_command..."	
			seconds_since_launch=0
			let "cmd_index = $processed_commands - 1"
			LSDEBUG "cmd_index=$cmd_index"
			execute_cmd "$full_command" $cmd_index # note double quotes, it's important to no enable autoconversion to array
			execution_status=$?
			duration=$SECONDS
			duration_message="$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
			LSDEBUG " Result of last cmd execution: $execution_status"
			
			COMMAND_EXIT_STATUSES[$processed_commands-1]=$execution_status
			COMMAND_RETRIES[$processed_commands-1]=$execution_attempt_no
			COMMAND_DURATION_SEC[$processed_commands-1]='0'
			
			if [ $execution_status -eq 0 ]; then
				LSINFO "  finished with SUCCESS in $duration_message"				
				break
			else				
				LSERROR "  finished with ERROR(exit code: $execution_status) in $duration_message"
				## todo incr attempt + check if not exceeded
				LSDEBUG " execution_attempt_no($execution_attempt_no), MAX_RETRIES($MAX_RETRIES)" 
				if [ $execution_attempt_no -eq $MAX_RETRIES ]; then
					LSINFO "  number of attempts ($execution_attempt_no) reached max retries ($MAX_RETRIES), will treat this as permanent error, see logs for details"
					((NUMBER_OF_COMMAND_FAILURES++))
					break
				fi
				LSDEBUG "increasing execution_attempt_no++"
				((execution_attempt_no++))
				LSDEBUG "sleeping for $SECONDS_BETWEEN_RETRIES seconds before next retry"
				sleep $SECONDS_BETWEEN_RETRIES				
			fi
		done
		
		if [ $processed_commands -ne $number_all_jobs ]; then
			LSDEBUG "sleeping for $SECONDS_BETWEEN_COMMANDS seconds before next command"
			sleep $SECONDS_BETWEEN_COMMANDS
		fi
		
		((processed_commands++))
	done
}

# print table with summary of execution
print_final_report(){

	LSINFO "==================================================================="
	
	for i in "${!COMMANDS[@]}"; do 
		#printf "%s\t%s\n" "$i" "${foo[$i]}"
		local -i exit_status=${COMMAND_EXIT_STATUSES[$i]}
		local -i duration=${COMMAND_DURATION_SEC[$i]}
		local -i retries=${COMMAND_RETRIES[$i]}
		local log=${COMMAND_LOGS[$i]}
		local cmd=$COMMANDS[$i]
		
		if [ $exit_status -eq 0 ]; then
			LSINFO "  SUCCESS in $retries retries and $duration sec => $cmd | $log"
		else	
			LSERROR "  ERROR in $retries retries and $duration sec => $cmd | $log"
		fi
	done
	
	LSINFO "==================================================================="
}

# Arguments:
# $1 - command to split
# Returns: store associative array in TEMP_COMMAND_ARRAY
# Example:
# command: processA='echo 1' will be translated as:
# ("label" -> "processA", "cmd"->"echo 1")
split_command(){
	local -r fullcommand="$1"	# i.e. processA='echo 1'
	# storing old IFS to restore after exit
	oIFS="$IFS"
	IFS='='
	LSDEBUG " fullcommand: $fullcommand"
	read -r id command <<< "$fullcommand"
	LSDEBUG " split id: $id  $command"		
	TEMP_COMMAND_ARRAY[label]=$id
	TEMP_COMMAND_ARRAY[cmd]=$command
	IFS=oIFS	# restore old IFS
	LSDEBUG " TEMP_COMMAND_ARRAY[cmd]: ${TEMP_COMMAND_ARRAY[cmd]}, TEMP_COMMAND_ARRAY[label]: ${TEMP_COMMAND_ARRAY[label]}"
}

#	convert command line arguments into read only global variables and log to console
# Arguments: none
validate(){

	[[ -z "$max_retries"  ]] && die "Missing argument max-retries"	
	[[ -z "$log_dir"  ]] && die "Missing argument log-dir"
	[[ ! -d "$log_dir" ]] && die "$log_dir does not exist or is not a directory"
	[[ -z "$log_prefix"  ]] && die "Missing argument log-prefix"	
	[[ ${#arguments[@]} -eq 0 ]] && die "At least one COMMAND need to be specified"
	
	LSINFO "Will use following configuration:"	
	
	LSINFO "  max-retries: $MAX_RETRIES"	
	LSINFO "  log-dir: $LOG_DIR"	
	LSINFO "  log-prefix: $LOG_PREFIX"		
	LSINFO "  sec_between_cmd: $SECONDS_BETWEEN_COMMANDS"
	LSINFO "  sec_between_retry: $SECONDS_BETWEEN_RETRIES"
	LSDEBUG "Will execute following commands in serial order:"
	
	
	for argument in "${arguments[@]}"; do
		LSDEBUG "processing: $argument"				
		COMMANDS+=("$argument")
	done
	
	local -i -r commands_size=${#COMMANDS[@]} 
	LSDEBUG "Size of COMMANDS array after decomposition: $commands_size"
	
}

# ==========================================================
#	main
main(){
	validate
	execute_all_commands
	print_final_report
		
	#	exit with failure if at least one failure occured
	if [ $NUMBER_OF_COMMAND_FAILURES -gt 0 ]; then
		die "Exiting with error as $NUMBER_OF_COMMAND_FAILURES failures occured"		
	fi	
}

main "$@"