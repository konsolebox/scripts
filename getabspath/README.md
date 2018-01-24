# getabspath

`getabspath()` is a function for shell scripts that intends to get the
strict absolute form of a path *(strict in a sense that the resulting
path would remain consistent even if another item is appended unto it)*, 
without relying on any external command if possible.  It accepts a
single argument, produces the absolute form of that path and saves it to
the variable __.

The scripts provided here provide an implementation of that function
that works for a specific shell like Bash, Ksh and Zsh.

| Script                | Target Shell                                        |
|-----------------------|-----------------------------------------------------|
| getabspath.bash       | Bash                                                |
| getabspath.ksh        | Ksh93                                               |
| getabspath.pdksh      | Public Domain Ksh and MirBSD Ksh                    |
| getabspath.sh+gwd     | Generic implementation that relies on gwd           |
| getabspath.sh+pwd     | Generic implementation that relies on pwd           |
| getabspath.sh+gwd+awk | Generic implementation that relies on gwd and awk   |
| getabspath.sh+pwd+awk | Generic implementation that relies on pwd and awk   |
| getabspath.zsh        | Zsh                                                 |
| gwd.sh                | Providse gwd() - a function that gets the current   |
|                       | working directory using the least expensive method. |
