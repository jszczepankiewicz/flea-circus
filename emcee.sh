#!/usr/bin/env bash

## Flea-circus: emcee.sh 
## Licensed under BSD
##
## This program is part of flea-circus. It validates configuration stored in layers.conf and processes.conf files. Usage:
##
##     @script.name [option] LAYER STOP/START
## 
## Where LAYER is name for group of processes that will be executed 
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

#	set default logging level to DEBUG for --verbose, INFO otherwise
if [ -z "$debug"  ]; then
	LS_LEVEL=LS_INFO_LEVEL 
else
	LS_LEVEL=LS_DEBUG_LEVEL 	
fi

declare -a LAYER_INDEXES
declare -a LAYER_NAMES
declare -a LAYER_PROCESSING_TYPES
declare -a LAYER_DELAY_AFTER_START
declare -a LAYER_MAX_RETRIES
declare -a LAYER_SECONDS_BETWEEN_RETRIES
declare -a LAYER_SECONDS_BETWEEN_COMMANDS

die () {
    LSERROR "$@"
    exit 1
}

read_layers(){

	LSINFO "Parsing layers.conf..."	
	[[ ! -f 'layers.conf'  ]] && die "Missing file layers.conf"	
	
	# index|name|processing_type(serial/concurrent)|delay_after_start|max-retries|seconds-between-retries|seconds-between-commands(serial-only, ignored in concurrent)
	local -i position=0
	OLDIFS=$IFS
	IFS=","
	
	while IFS=',' read -r line || [[ -n "$line" ]]; do
		read -r index name processing_type delay_after_start max_retries seconds_between_retries seconds_between_commands <<< "$line"
		LSDEBUG " index:$index|name:$name|processing_type:$processing_type|delay_after_start:$delay_after_start|max-retries:$max-retries|seconds_between_retries:$seconds_between_retries|seconds_between_commands:$seconds_between_commands"
		LAYER_INDEXES[$position]=$index
		LAYER_NAMES[$position]=$name
		LAYER_PROCESSING_TYPES[$position]=$processing_type
		LAYER_DELAY_AFTER_START[$position]=$delay_after_start
		LAYER_MAX_RETRIES[$position]=$retries
		LAYER_SECONDS_BETWEEN_RETRIES[$position]=$seconds_between_retries
		LAYER_SECONDS_BETWEEN_COMMANDS[$position]=$seconds_between_commands
		((position++))
	done < layers.conf

	
	LSINFO "Loaded $position layers"
	IFS=$OLDIFS
}


main(){
	read_layers
	
	exit 0
}

main "$@"