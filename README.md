Erlang project version management
==============

Goal
-----------
`ver_mgmt.mk` was created to track software versions automagically.

It is designed to work with [erlang.mk](http://erlang.mk/)

Configuration
---------
Example `Makefile` in your `master` branch:
```
PROJECT = hello_world

DEPS = hello world ibrowse
SLAVE_DEPS = hello world # These repositories are to have the same version branch as this (master) one

dep_hello = git git@github.com:somebody/hello.git master
dep_world = git git@github.com:somebody/world.git master

include erlang.mk
include ver_mgmt.mk
```

Synchronize versions
-----
`make bump VER=1.4`

After that the branch `release-1.4` will be created or checked-out in curent repository and its slaves.
