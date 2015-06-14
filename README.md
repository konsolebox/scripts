# scripts

Repository for various scripts I make.

#### binfind.sh

Searches for binary files based on the value of `$PATH`.

#### getabspath/*

Scripts that implement getabspath() for various shells.  getabspath() is a
function for shell scripts that's intended to get the strict absolute form
of a path without relying on an external commands if possible.

#### init/build-and-copy.sh

A script I ended up making to automate building of my custom initrd.

#### killtree.sh

Sends signals to process trees with style.

The script also contains reusable functions for working with process
trees.

#### libfind.sh

Finds library files by keywords or expressions in directories specified
by /etc/ld.so.conf and its subfiles, or in common library directories
specified in an integrated list.

#### manfind.sh

Searches for manual pages based on `$MANPATH`.

#### notepad++.sh

I use this wrapper script to easily run wine-emulated Notepad++.

#### rcopy.sh

Copies files along with their dependencies to a virtual root directory.
The resulting file's path is reproduced based on its source.

#### tcpdump-master.sh

The script is a tcpdump service starter and manager.  It can also
automatically delete files older than C days, and reduce the size of
the main log file if it's already larger than N bytes.

#### uuidfstab.sh

Converts device paths in a fstab file to UUID forms.
