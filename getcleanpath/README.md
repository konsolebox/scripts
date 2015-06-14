# getcleanpath

`getcleanpath()` is a function for shell scripts that intends to get the
clean absolute form of a path without relying on any external command if
possible.  It accepts a single argument, produces the absolute form of
that path and saves it to the variable __.

The scripts provided here provide an implementation of that function
that works for a specific shell like Bash, Ksh and Zsh.

| Script                  | Target Shell |
|-------------------------|--------------|
| getcleanpath.bash       | All versions of Bash starting 3.0. |
| getcleanpath.bash-2.05b | Bash 2.05b or newer |
| getcleanpath.bash-2.04  | Bash 2.04 or newer  |
| getcleanpath.ksh        | Original Ksh |
| getcleanpath.pdksh      | Public Domain Ksh |
| getcleanpath.sh         | Generic implementation for all Bourne shell based shells that relies on pwd and a subshell |
| getcleanpath.sh+awk     | Generic implementation that relies on pwd and awk |
| getcleanpath.zsh        | Zsh |
