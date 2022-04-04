# scripts

A repository for various scripts I make.

#### binfind.bash

Searches for binary files based on the value of `$PATH`.

#### build-and-copy.bash

A script I use to automate building of initrd image.

#### dnscrypt-proxy-multi.rb

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

#### gdb-completion.bash

A completion script for gdb.

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

#### killtree.bash

Sends signals to process trees with style.

The script also contains reusable functions for working with process
trees.

#### killtree-lite.bash

A less poetic version of killtree.

#### libfind.bash

Finds library files by keywords or expressions in directories specified
by /etc/ld.so.conf and its subfiles, or in common library directories
specified in an integrated list.

#### manfind.bash

Searches for manual pages based on `$MANPATH`.

#### map-partitions.bash

This tool maps partitions in a block device to logical devices using
dmsetup and sfdisk.

#### rake-completion.bash

A completion script for rake.

#### rcopy.bash

Copies files along with their dependencies to a virtual root directory.
The resulting file's path is reproduced based on its source.

#### tcpdump-master.bash

The script is a tcpdump service starter and manager.  It can also
automatically delete files older than C days, and reduce the size of
the main log file if it's already larger than N bytes.

I wrote it back in 2010 for an LQ thread.  Right now tcpdump already has
most of its features.

#### trim-trailing-spaces.bash

Removes trailing spaces in files.

#### uuidfstab.bash

Converts device paths in a fstab file to UUID forms.
