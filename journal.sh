#!/bin/bash

declare -A ENV=(
    [src]=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")") # path to project root
    [core]="$(which jrnl 2>/dev/null || echo 'NOT FOUND')"
    [config]="$JRNL_CONFIG" 
    [data]="${JRNL_DATA:-$HOME/.jrnl}"
    [log]="${LOGS:-$HOME/.log}"
    [cache]="${CACHE:-$XDG_CACHE_HOME}/jrnl"
    [message]='' # post-execution messages and warnings go here
    # [pwd]=$(pwd)
    [error]=0
    [argless]=$([[ $# -eq 0 ]] && echo 1 || echo 0)
    [notebook]="${JRNL_NOTEBOOK:-main}"
)

declare -A FILE=(
    [log]="${ENV[log]}/jrnl.log"
    [help]="${ENV[src]}/help.txt"
    [write_mode]="${ENV[cache]}/write.mode.bool"
)

declare -A ERROR=(
    [0]='OK'
    [150]='ERROR 150: '
)

declare -A ARG=(
    # CACHE="$HOME/.cache" # now ENV[cache]
    # DEBUG=0              # now ARG[debug]
    # EDIT=0               # now ARG[edit]
    # DELETE=0             # now ARG[delete]
    # HOME_DIR=''          # now ENV[root]
    # INPUT_ARGS="$@"      # now ARG[input]
    # LOG=''               # now ENV[log]
    # JRNL=''              # now ENV[core]
    # OK=1                 # now ENV[error] -eq 0
    # WRITE_MODE='off'     # now ARG[write]
    # WRITE_MODE_INDICATOR_FILE="$CACHE/jrnl/" # now FILE[write_mode]
    # AMEND=0              # now ARG[amend]
    [input]="$@"
    [unknown]='null'      # unknown args
    [debug]=0
    [help]=0
    [notebook]='null'
    [query]=1             # query mode is ON by default
    [write]=0             # WARNING: must be cached to avoid overwrite
    [edit]=0              # WARNING: set FILE[write_mode] to true
    [delete]=0
    [amend]=0             # WARNING: set FILE[write_mode] to true
    [filter]='null'
    # [template]='null'                    
    # [on_date]='null'
    # [today_in_history]=False
    # [month]='null'
    # [day]='null'           
    # [year]='null'
    # [start_date]='null'
    # [end_date]='null'
    # [strict]=False
    # [starred]=False                    
    # [tagged]=False
    # [limit]='null'
    # [excluded]=[]
    # [change_time]='null'
    # [export]=False
    # [tags]=False,             
    # [short]=False
    # [config_override]=''
    # [config_file_path]=''              
    # [text]=''
    # [exclude_starred]=False
    # [exclude_tagged]=False
)

log() { echo "$@" >> "$LOG"; };

function main() {
    initialize   # setup environment and check for missing files
    parse "$@"   # break input for analysis
    # validate     # validate the operation
    # dispatch     # execute the operation
    # terminate    # execute post-script tasks regardless of operation
    # # parse_args $INPUT_ARGS
    # [[ "$1" == "debug" ]] && shift && reveal_variables 
    # [[ $OK -eq 1 ]] && route_args "$@"
}

initialize() {
    check_env_exists
    source_env
    prepare_true_command
}

parse() {

    local last_option='unknown'
    
    # Iterate over arguments using a while loop
    while [[ $# -gt 0 ]]; do
        case "$1" in

            debug | --debug)
                ARG[debug]=1 ;
                ;;
            help | --help | -h)
                ARG[help]=1 ;
                ;;
            stat)
                ARG[stat]=1 ;
                ;;               
            config)
                ARG[config]='' ;
                last_option='config' ;
                ;;
            job | -j)
                ARG[job]='' ;
                last_option='job' ;
                ;;
            cv | resume | -c)
                ARG[cv]="" ;
                last_option='cv' ;
                ;;
            template* | tmpl | -t)
                ARG[template]='' ;
                last_option='template' ;
                ;;
            doc | -d)
                ARG[doc]='' ;
                last_option='doc' ;
                ;;
            --render)
                # [[ "$last_option" == 'cv' ]]
                ARG[render]='' ;
                last_option='render' ;
                ;;
            link | -l)
                ARG[link]='' ;
                last_option='link' ;
                ;;
            null)
                ENV[message]+='null has special meaning, rejected\n' ;
                ;;
            --)
                last_option='unknown' ; # resets last option
                ;;
            *)
                # if last option is unknown clear ARG[unknown]
                [[ "$last_option" == 'unknown' ]] && is_null "${ARG[unknown]}" && ARG[unknown]=''
                # last option specified captures the argument
                ARG[$last_option]="${ARG[$last_option]} $1" ;
                ;;

        esac ; shift # discard argument
    done
}

route_args() {

    log "jrnl-main: ARGS = $@"

    # Put non-terminating case first
    # --printenv ) 
    #         shift; printenv=1 ;;

    # terminating cases
    case "$1" in
        # NO ARGUMENT

        '') show_today_jrnl ;;

        # SPECIAL COMMANDS

        -\?) 
            print_info ;; # such as context, number of todos, consumed status, etc...
        --)
            shift; bypass_wrapper "$@";; # go directly to the true jrnl program
        --amend | -a | amend)
            export AMEND=1 ;
            export WRITE_MODE='on' ;
            shift ; amend ;;
        --date  | -d | dat*) 
            shift; view_journal_on_date "$@" ;;
        --template | -T | temp*) 
            load_template "$2" ;;
        --todo | -t)
            edit_today_todo "$@" ;;
        --undo | -u | und*)
            shift; execute_true_jrnl --delete -1 ;;
        --write | -w | wri*) 
            shift; "$HOME_DIR/jrnl-write.sh" "$@" ; exit "$?" ;;
        --no-editor | -wn | -nw )
            shift; "$HOME_DIR/jrnl-write.sh" "-n" ; exit "$?" ;;
        src  | -D) 
            shift; debug_code "$@" ;;
        git    | -g) 
            shift; execute_git "$@" ;;
        config  | -C) 
            shift; config_jrnl "$@" ;;
        cont*  | -c) 
            shift; context "$@" ; exit "$?";;
        push   | -p) 
            shift; push_to_remote ;;
        view   | ?d) 
            view_entries_in_terminal "$@" ;;
        yest*)
            view_journal_yesterday "$@" ;;

        # Cases where $1 begins with '-' or '@', pass directly to jrnl without processing
        -* | @*) $JRNL $@ ;;

        # If no case matched above, then treat it as a filter by default
        *) filter_journal "$@"

    esac
}

check_env_exists() {
    export HOME_DIR="$(dirname "$(readlink -f "$0")")"
    export env="$HOME_DIR/.env"
    # env not exist
    if [[ ! -f "$env" ]]; then echo "NO $env FOUND. Create one in $HOME_DIR"; exit 1; fi
}

source_env() {
    tmp=$HOME_DIR
    # Load config variables
    source "$HOME_DIR/.env"
    # verify contents, issue warning if needed
    if [[ "$HOME_DIR" != "$tmp" ]]; then echo "Warning: HOME_DIR [$HOME_DIR] not matching actual parent ($tmp)"; fi
    # does LOG exists?
    if [[ ! -f "$LOG" ]]; then
        echo "$LOG DOES NOT EXIST IN $tmp/.env. Will send output to $tmp/jrnl.log instead."
        export LOG="$tmp/jrnl.log"
    fi
}

parse_args() {
    EDIT=0
    DELETE=0
    ON=0
    FUCK=0
    SHIT=0
    last_opt=''

    for arg in $@; do
        echo "$arg"
        sleep 0.1
    done

    # Iterate over arguments using a while loop
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --edit)
                export EDIT=1
                last_opt='--edit'
                shift  # Move to next argument
                ;;
            delete)
                export DELETE=1
                last_opt='delete'
                shift
                ;;
            on)
                export ON=1
                shift
                ;;
            *)
                # Handle unknown argument
                echo "$last_opt: $1"
                shift
                ;;
        esac
    done

    echo "EDIT=$EDIT"
    echo "DELETE=$DELETE"
    echo "ON=$ON"
}

prepare_true_command() {
    og_jrnl_cmd="${ENV[core]}"
    notebook="${ENV[notebook]}"
    config="${ENV[config]}"

    if [[ $og_jrnl_cmd == "NOT FOUND" ]]; then echo "Command jrnl is NOT FOUND. Make sure \$(which jrnl) returns the path to the original command."; exit 1; fi
    if [[ ! -f "$config" ]]; then echo "CONFIG FILE $config DOES NOT EXIST." ; exit 2; fi

    export JRNL="$og_jrnl_cmd $notebook --config-file $config"
    log "$JRNL"
}

amend() {
    $JRNL -1 --edit
}

bypass_wrapper() {
    #"$JRNL" "$@"
    echo "that shit wont work"
}

config_jrnl() {
    if [[ $(systemd-detect-virt) == "wsl" ]]; then
        "$EDITOR" "$CONFIG_WSL"
    else
        "$EDITOR" "$CONFIG"
    fi
}

context() {
    context_value=$(get_context)
    case "$1" in
        -? | "")                      print_selected_journal=1 ; list_context=1 ;;
        -s | selected)                print_selected_journal=1 ;;
        -l | list)                    list_context=1 ;;
        -n | none)                    set_context='none' ;;
        -w | work)                    set_context='work' ;;
        *)                            warn 'Usage: $ jrnl context [ list | none | acad | work | flex ]'; exit 1 ;;
    esac
    if [[ -n $print_selected_journal ]]; then
        case "$context_value" in
            none)  warn "Main journal selected." ;;
            work)  warn "Work journal selected." ;;
            *)     err  "No journal named $context_value exists." ; warn "this could be a bug check function `context`" ; exit 1 ;;
        esac
    fi
    if [[ -n $list_context ]]; then
        echo -e "  -none\n  -work"
    fi
    if [[ -n $set_context ]]; then
        echo "$set_context" > "$CONTEXT"
        warn "Context set to [$set_context]"
    fi
}

debug() {
    # show debug message if enabled
    if [[ $DEBUG -eq 1 ]]; then
        echo -e "\e[36m$@\e[0m"
    fi
}

debug_code() {
    if [[ -n "$@" ]]
        then editor="$@"
        else editor="micro"
    fi
    "$editor" "$0"
    exit "$?"
}

edit_today_journal() {
    $JRNL -on today --edit
    exit "$?"
}

edit_today_todo() {
    $JRNL -on today -contains 'TODO' $2
}

execute_git() {
    git -C "$DOMAIN" "$@"
    exit "$?"
}

execute_true_jrnl() {
    J=$(get_notebook)
    debug "$jrnl" "$J" "$@"
    "$jrnl" "$J" "$@" ; x="$?"
    context selected
    exit "$x"
    #confirmation code
    # warn "Do you want to execute $jrnl $C $@ ? [Y/n] "
    # read -r answer
    # 
    # if [ -z "$answer" ]; then
        # answer="yes"  # Default to "yes" if user just presses Enter
    # fi
    # 
    # if [ "$answer" == "yes" ] || [ "$answer" == "y" ]; then
        # $jrnl $C $@
    # elif [ "$answer" == "no" ] || [ "$answer" == "n" ]; then
        # echo "Exiting..."
        # # Do nothing, just exit
    # else
        # echo "Invalid input. Defaulting to 'no'."
        # echo "Exiting..."
        # # Do nothing, just exit
    # fi
}

filter_journal() {
    # Capture the output of the journal command
    search_result=$($JRNL -contains "$@")

    if [[ -z $search_result ]]; then exit 0; fi

    # $JRNL -contains "$@" | grep --color=always -E "$@|$" | less -R

      # Capture the output of the journal command
    output=$($JRNL -contains "$@" 2> /dev/null | grep --color=always -E "$@|$")

    # Use `grep` to check if the output is "no entries found" and handle accordingly
    echo "$output" | less -R
}

# sub-command, PUT IN ITS OWN SCRIPT TODO:
jrnl_write() {
    case "$1" in
        '') new_entry_with_no_editor ;;
        *) echo "jrnl-write: I don't know what to do with $1 yet" ;;
    esac
    exit "$?"
}

# generate short form uuid
generate_uuid() {
    uuid=$(uuidgen | head -c 8)
    # Using ANSI escape codes to style the output
    echo -e "entry id: \033[1;37;41m$uuid\033[0m (must include manually!)"
}

load_template() {
    WRITE_MODE_INDICATOR_FILE="${FILE[write_mode]}"

    if [[ -z "$TEMPLATES" ]]; then err "\$TEMPLATES is NOT defined in $HOME_DIR/.env!"; exit 88; fi;
    template_file="$TEMPLATES/$1"
    echo $template_file
    if [[ -d "$template_file" ]]; then err "$template_file is a directory"; exit 89; fi
    if [[ ! -f "$template_file" ]]; then err "$template_file DOES NOT EXIST"; exit 90; fi
    generate_uuid
    # write mode ON
    echo 'on' > "$WRITE_MODE_INDICATOR_FILE"
    $JRNL --template "$template_file"
    # write mode OFF
    echo 'off' > "$WRITE_MODE_INDICATOR_FILE"
    exit "$?"
}

get_context() {
    if [[ ! -f "$CONTEXT" ]]; then
        dirname=$(dirname $CONTEXT)
        mkdir -pv $dirname
        echo "none" > "$CONTEXT"
        echo "none"
    else
        cat "$CONTEXT"
    fi
}

get_notebook() {
    local context=$(get_context)
    case "$context" in
        none)  echo 'main'; exit 0 ;;
        work)  echo 'work'; exit 0 ;;
        *) warn "unverified journal, see get_journal()" ; echo $context ;;
    esac
}

print_info() {
    context selected
    context list
    exit 0
}

# Help function to display usage information and option descriptions
print_help() {
    # # ANSI color codes for colors without using \e[33m and \e[31m
    # GREEN='\033[0;32m'
    # BLUE='\033[0;34m'
    # NC='\033[0m' # No Color
# 
    # echo "Usage: $(basename "$0") [OPTIONS]"
    # echo "Options:"
    # for option in "${!option_descriptions[@]}"; do
        # printf "  ${GREEN}%-12s${NC} %s\n" "$option" "${option_descriptions[$option]}"
    # done
    # exit 0
    echo 'case "$1" in
            "")   new_entry "$@" ;;
            -?) print_info ;; # such as context
            .) view_journal_today "$@" ;;
            ..) view_journal_yesterday "$@" ;;
            help   | -h) shift; print_help ;;
            debug  | -D) shift; debug_code "$@" ;;
            git    | -g) shift; execute_git "$@" ;;
            config | -C) shift; config_jrnl "$@" ;;
            context| -c) shift; context "$@" ;;
            update | -u) shift; update "$DOMAIN" -add "." -commit "updating from $HOSTNAME" ;;
            push   | +p) shift; push_to_remote ;;
            view   | ?d) view_entries_in_terminal "$@" ;;
            *) execute_true_jrnl "$@" ;;
        esac'
    exit 0
}

# exit-function
push_to_remote() {
    git -C $DOMAIN add .
    git -C $DOMAIN commit -m "updating from $HOSTNAME"
    git -C $DOMAIN push
    exit "$?"
}

# Loop through the keys of the associative array and print key-value pairs
reveal_variables() {
    local yellow="\033[33m"
    local green="\033[32m"
    local red="\033[31m"
    local purple="\033[35m"
    local cyan="\033[36m"
    local reset="\033[0m"

    echo -e "--- ARGUMENTS ---"
    for key in "${!ARG[@]}"; do
        value="${ARG[$key]}"
        value="${value%"${value##*[![:space:]]}"}"  # Trim trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"  # Trim leading whitespace
        color="$reset"

        if [[ $value == 'null' ]]; then
            value=""  # Null value
        elif [[ -z $value ]]; then
            value="EMPTY"  # Empty string
            color=$cyan    # Empty value
        elif [[ $value == '1' ]]; then
            color=$green   # True value
        elif [[ $value == '0' ]]; then
            color=$red     # False value
        fi

        printf "${yellow}%-20s${reset} : ${color}%s${reset}\n" "$key" "$value"
    done

    echo -e "--- ENVIRONMENT ---"
    for key in "${!ENV[@]}"; do
        value="${ENV[$key]}"
        value="${value%"${value##*[![:space:]]}"}"  # Trim trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"  # Trim leading whitespace
        color="$reset"

        if [[ $value == 'null' ]]; then
            value=""  # Null value
        elif [[ -z $value ]]; then
            value="EMPTY"  # Empty string
            color=$cyan    # Empty value
        elif [[ $value == '1' ]]; then
            color=$green   # True value
        elif [[ $value == '0' ]]; then
            color=$red     # False value
        fi

        printf "${yellow}%-20s${reset} : ${color}%s${reset}\n" "$key" "$value"
    done

    echo -e "--- FILES ---"
    for key in "${!FILE[@]}"; do
        value="${FILE[$key]}"
        value="${value%"${value##*[![:space:]]}"}"  # Trim trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"  # Trim leading whitespace
        color="$reset"

        if [[ $value == 'null' ]]; then
            value=""  # Null value
        elif [[ -z $value ]]; then
            value="EMPTY"  # Empty string
            color=$cyan    # Empty value
        elif [[ $value == '1' ]]; then
            color=$green   # True value
        elif [[ $value == '0' ]]; then
            color=$red     # False value
        fi

        printf "${yellow}%-20s${reset} : ${color}%s${reset}\n" "$key" "$value"
    done
}

show_today_jrnl() {
    warn "Today's entries:"
    view_journal_today
    warn "To read journal on specific date, do jrnl -d DATE"
    warn "To start writing, do jrnl -w"
    warn "Use one of the available templates in $JRNL_DATA/templates!"
    exit 0
}

get_pager() {
    if [ -f '/bin/bat' ]; then
        echo 'bat -p'
    else
        echo 'less -R'
    fi
}

# exit function
view_entries_in_terminal() {
    context selected
    J=$(get_notebook)
    length="${1:0:1}"
    limit="$2"
    debug "d = $length"
    _date=$(date -d "$length days ago" "+%a %b %e %Y")
    debug "date = $_date"
    "$jrnl" "$J" -on $(date -d "$_date" +%F) -n $limit
    warn "Viewing entries for $_date"
    exit "$?"
}

view_journal_today() {
    pager=$(get_pager) 
    $JRNL -on today | $pager
    echo "$JRNL -on today" >> "$LOG"
}

view_journal_on_date() {
    J=$(get_notebook)
    warn "Journal: $J"
    date_args="$*"
    date=$(date -d "$date_args" +"%Y-%m-%d")
    if [ -z "$date" ]; then exit 9; fi
    log "$JRNL -on $date"
    $JRNL -on $date ; x="$?"
    exit "$x"
}

view_journal_yesterday() {
    J=$(get_notebook)
    $JRNL "$J" -on yesterday ; x="$?"
    context selected
    exit "$x"
}

warn() { echo -e "\e[33m$@\e[0m" >&2; }
err()  { echo -e "\e[31m$@\e[0m" >&2; }

main "$@"
reveal_variables