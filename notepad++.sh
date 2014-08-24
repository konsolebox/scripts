#!/bin/bash

# --------------------------------------------------------------------
# notepad++
#
# I use this wrapper script to easily run wine-emulated Notepad++.
# I install it in the system as /usr/local/bin/notepad++.
# --------------------------------------------------------------------

if [[ -e "$HOME/.wine/drive_c/Program Files/Notepad++/notepad++.exe" ]]; then
	env WINEPREFIX="$HOME/.wine" wine "C:/Program Files/Notepad++/Notepad++.exe" "$@"
elif [[ -e "$HOME/.wine/drive_c/Program Files (x86)/Notepad++/notepad++.exe" ]]; then
	env WINEPREFIX="$HOME/.wine" wine "C:/Program Files (x86)/Notepad++/Notepad++.exe" "$@"
else
	echo "Notepad++.exe can't be found."
fi
