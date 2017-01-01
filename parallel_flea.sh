#!/usr/bin/env bash

# please do not alter below comment with double hash. This is for easyoptions.sh script to automatically parse & build global state
## Flea-circus: parallel_flea.sh 
## Licensed under BSD
##
## This program is part of flea-circus. It executes provided list of commands in parallel and if failed reattempts. Usage:
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

# ==========================================================
#	libraries

source log.sh || exit 1
source easyoptions.sh || exit 1

# ==========================================================
# global variables

declare -i NUMBER_OF_COMMAND_FAILURES=0
declare -i -r MAX_RETRIES=$max_retries
declare -r LOG_DIR=$log_dir
declare -r LOG_PREFIX=$log_prefix
declare -r -i SECONDS_BETWEEN_COMMANDS=${sec_between_cmd:=0}
declare -r -i SECONDS_BETWEEN_RETRIES=${sec_between_retry:=0}

#	set default logging level to DEBUG for --debug, INFO otherwise
if [ -z "$debug"  ]; then
	LS_LEVEL=LS_INFO_LEVEL 
else
	LS_LEVEL=LS_DEBUG_LEVEL 	
fi
# ==========================================================
# functions
die () {
    LSERROR "$@"
    exit 1
}


# validates configuration passed to this scripts
# dies if something is wrong. Otherwise sets global variables
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
	LSDEBUG "Will execute following commands in parallel:"
		
	for argument in "${arguments[@]}"; do
		LSDEBUG "processing: $argument"				
		COMMANDS+=("'$argument'")
	done
	
	local -i -r commands_size=${#COMMANDS[@]} 
	LSDEBUG "Size of COMMANDS array after decomposition: $commands_size"
	
	# validating whether parallel command is accessible
	hash parallel 2>/dev/null || die "Missing 'parallel' command. Make sure it is installed in current directory or globally"
}

# executes parallel command. Sets NUMBER_OF_COMMAND_FAILURES to
# 0 if there were no failures or to number of failures if at least 1 occured. 
# args: none (all taken from global variables)
execute_parallel(){
	# parallel 
	local args	
	local cmd="parallel --delay $SECONDS_BETWEEN_COMMANDS ./serial_flea.sh --max-retries=$MAX_RETRIES --log-dir=$LOG_DIR --log-prefix=$LOG_PREFIX --sec-between-retry=$SECONDS_BETWEEN_RETRIES ::: ${COMMANDS[@]}"
	LSINFO "About to execute: $cmd"
	eval "$cmd"	# result of last command in bash is automatically returned from this function to calling context(stored in $?)
}

# prints report about each job status. 
# args: none (parses gnu parallel job report to get detailed information)
print_final_report(){
	# TBD
	LSDEBUG "Summary of execution: "
}

main(){
	
	validate
	execute_parallel
	NUMBER_OF_COMMAND_FAILURES=$?
	print_final_report
		
	#	exit with failure if at least one failure occured
	if [ $NUMBER_OF_COMMAND_FAILURES -gt 0 ]; then
		die "Exiting with error as $NUMBER_OF_COMMAND_FAILURES failures occured"		
	else
		LSINFO "Execution successful"
	fi	
}

main "$@"