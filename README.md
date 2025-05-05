# scripts

A repository for various scripts I make.

### binfind.bash

Searches for binary files based on the value of `${PATH}`.

### build-initramfs.bash

Automates building of an initrd image using the files and directories in
a specified directory.

### cd.bash

A simple and convenient enhancement wrapper for **cd**.

### dnscrypt-proxy-multi.rb

A Ruby script that runs multiple instances of **dnscrypt-proxy**.

It parses a CSV file and makes use of the entries found in it as target 
remote services when creating instances of **dnscrypt-proxy**.

Remote services are checked for availability before an instance of 
**dnscrypt-proxy** is used to connect to them.

An FQDN can also be used to check if a remote service is able to 
resolve names.

The script waits for all instances to exit before it exits.  It also 
automatically stops them when it receives a SIGTERM or a SIGINT signal.

### getabspath/*

Scripts that implement **getabspath** for POSIX-compliant shells.

**getabspath** is a shell function that returns the strict absolute 
form of a given path.

Similar to **realpath**, it converts the input to its simplified 
absolute form using the current directory as a reference but does not 
resolve symbolic links and ensures the output’s trailing slash matches 
the input’s: one or more trailing `/` yields a single `/`, otherwise 
none.

A `/` or `.` may be added to match the input’s trailing slash presence, 
distinguishing strict from regular absolute paths.

### getcleanpath/*

Scripts that implement **getcleanpath** for POSIX-compliant shells.

**getcleanpath** is a shell function that returns the absolute form of 
a given path.

Similar to **realpath**, it converts the input to its simplified 
absolute form using the current directory as a reference but does not 
resolve symbolic links.

Unlike **getabspath**, it omits any trailing `/` except for the root 
directory.

### git/git-amend-date-using-reference.bash

Updates the current commit's date using another commit's date as
reference.

### git/git-checkout-last-version.bash

Extracts the last version of a file before it was removed from git.

### git/git-diff-blame.rb

Annotates each line in a diff hunk with author and commit information
like **git blame**'s output.

### git/git-move.bash

Rebases commits in a tree onto a new base commit within the same tree.

### hist.bash

Searches `~/.bash_history` for entries matching specified keywords.

### hyphenate.rb

Renames files and directories to the hyphenated version of their
filename.

### killtree.bash

Sends signals to process trees with style.

The script also contains reusable functions for managing process trees.

### killtree-lite.bash

A less poetic version of **killtree**.

### libfind.bash

Finds library files by keywords or expressions in directories specified
by `/etc/ld.so.conf` and its subfiles, or in common library directories
specified in an integrated list.

### manfind.bash

Searches for manual pages based on `${MANPATH}`.

### map-partitions.bash

This tool maps partitions in a block device to logical devices using
**dmsetup** and **sfdisk**.

### rcopy.bash

Copies files along with their dependencies to a virtual root directory.

The resulting file's path is reproduced based on its source's location.

### tail-follow-grep.bash

Basically a wrapper for `tail -f` and `grep --line-buffered`.

### tcpdump-master.bash

A script to start and manage a **tcpdump** service.

It can automatically delete files older than a specified number of days
and truncate the main log file if it exceeds a specified size in bytes.

This was originally written in 2010 for a LinuxQuestions.org thread but
**tcpdump** includes most of its features now.

### trim-trailing-spaces.bash

Removes trailing whitespace from files.

### uuidfstab.bash

Replaces device paths in an fstab file with their UUID equivalents.

### xn.rb

Renames files and directories based on their 160-bit KangarooTwelve
checksum.

It supports recursive renaming and avoids naming conflicts among files
and directories with distinct content by appending supplemental
suffixes.
