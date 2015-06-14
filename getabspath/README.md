# getabspath

`getabspath()` is a function for shell scripts that intends to get the
strict absolute form of a path *(strict in a sense that the resulting
path would remain consistent even if another item is appended unto it)*, 
without relying on any external command if possible.  It accepts a
single argument, produces the absolute form of that path and saves it to
the variable __.

The scripts provided here provide an implementation of that function
that works for a specific shell like Bash, Ksh and Zsh.

| Script                | Target Shell |
|-----------------------|--------------|
| getabspath.bash       | All versions of Bash starting 3.0. |
| getabspath.bash-2.05b | Bash 2.05b or newer |
| getabspath.bash-2.04  | Bash 2.04 or newer  |
| getabspath.ksh        | Original Ksh |
| getabspath.pdksh      | Public Domain Ksh |
| getabspath.sh         | Generic implementation for all Bourne shell based shells that relies on pwd and a subshell |
| getabspath.sh+awk     | Generic implementation that relies on pwd and awk |
| getabspath.zsh        | Zsh |
