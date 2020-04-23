#!/bin/bash

############################################################
# brew must be installed - it will install nodejs + a package
#
# $ brew install nodejs
# $ cd $HOME && npm install cocoa-dialog
#
############################################################
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
    echo "waiting to start $USERSCRIPT_FOR_DEBUGGING"
    cat <<EOF > $HOME/dialog.js
    (async () => {
    await require('cocoa-dialog')('msgbox', {
                title: 'Debug Script',
                text: 'Make a snapshot in virtualizer',
                button1: 'OK'
        });
    })();
EOF
    node $HOME/dialog.js
    rm $HOME/dialog.js
    $USERSCRIPT_FOR_DEBUGGING $1
fi

echo "running user script in $CHROOT"
