# scripts

Repository for various scripts I make.

#### binfind.sh

Searches for binary files based on the value of `$PATH`.

#### dnscrypt-proxy-multi

A Ruby script that runs multiple instances of dnscrypt-proxy.

It parses a CSV file and makes use of the entries found in
it as target remote services when creating instances of
dnscrypt-proxy.  Remote services are checked for
availability before an instance of dnscrypt-proxy is used
to connect to them.  An FQDN can also be used to check if
a remote service can resolve names.

The script waits for all instances to exit before it
exits.  It also automaticaly stops them when it receives
SIGTERM or SIGINT.

#### getabspath/*

Scripts that implement getabspath() for various shells.  getabspath() is
a function for shell scripts that's intended to get the strict absolute
form of a path *(strict in a sense that the resulting path would remain
consistent even if another item is appended unto it)*, without relying
on an external command if possible.

#### getcleanpath/*

Scripts that implement getcleanpath() for various shells. 
getcleanpath() is similar to getabspath() but it doesn't care about the
format of its input to base on for its output.  It would always produce
an output similar to realpath where the path would never end in / unless
it's the root directory itself.

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
