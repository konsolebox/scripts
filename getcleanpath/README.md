# getcleanpath

`getcleanpath()` is a function for shell scripts that intends to get the
clean absolute form of a path without relying on any external command if
possible.  It accepts a single argument, produces the absolute form of
that path and saves it to the variable __.

The scripts provided here provide an implementation of that function
that works for a specific shell like Bash, Ksh and Zsh.

| Script                  | Target Shell                                       |
|-------------------------|----------------------------------------------------|
| getcleanpath.bash       | Bash                                               |
| getcleanpath.ksh        | Ksh93                                              |
| getcleanpath.pdksh      | Public Domain Ksh and MirBSD Ksh                   |
| getcleanpath.sh+gwd     | Generic implementation that relies on gwd          |
| getcleanpath.sh+pwd     | Generic implementation that relies on pwd          |
| getcleanpath.sh+gwd+awk | Generic implementation that relies on gwd and awk  |
| getcleanpath.sh+pwd+awk | Generic implementation that relies on pwd and awk  |
| getcleanpath.zsh        | Zsh                                                |
| gwd.sh                  | Providse gwd() - a function that gets the current  |
|                         | working directory using the least expensive        |
|                         | method.                                            |
