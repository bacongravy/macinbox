#!/bin/bash

#
#
# Debugging user-scrpts can be a pain!
#
# So use this user script with the --user-script option
# put the script you want to debug in $HOME/user-script.sh
#
# when macinbox is calling the userscript - it arrives here
# make a snapshot of your virtualizer e.g. vbox or fusion
#


# arguments are zero based
if [ "$#" -eq 0 ]; then
    echo "Illegal number of parameters - we expect the base path here"
    exit 0
fi

export CHROOT=$1

# debug hack
export USERSCRIPT_FOR_DEBUGGING=$HOME/user-script.sh
if [ -f $USERSCRIPT_FOR_DEBUGGING ]; then
    echo "make a snapshot in your virtualizer"
    echo "press enter to start $USERSCRIPT_FOR_DEBUGGING"
    read
    $USERSCRIPT_FOR_DEBUGGING $1
fi

echo "running user script in $CHROOT"
