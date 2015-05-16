# scripts

Repository for various scripts I make.

#### binfind.sh

Searches for binary files based on the value of `$PATH`.

#### init/build-and-copy.sh

A script I ended up making to automate building of my custom initrd.

#### libfind.sh

Finds library files by keywords or expressions in directories specified
by /etc/ld.so.conf and its subfiles.  Expressions can be in the form of
normal patterns, regular expressions, or extended regular expressions
which can be changed through an option.  It also has an integrated list
of common directories that can be used over those specified in files.

#### manfind.sh

Searches for manual pages based on `$MANPATH`.

#### notepad++.sh

I use this wrapper script to easily run wine-emulated Notepad++.

#### rcopy.sh

Copies files along with their dependencies to a virtual root directory.
The resulting file's path is reproduced based on its source.
