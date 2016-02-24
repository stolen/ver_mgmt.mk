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

Debian packages
--------
You can create automatically-versioned Debian packages.

For each package you want to build, create a directory `pkg/<package_name>` containing:
  * `debian` directory with all the debian stuff except `changelog` (it will be generated)
  * `dupload.conf` with repository details

Now you can use following `make` targets:
  * `build_deb PKG=<package_name>` for building a single package using `debuild`
  * `deb` for building all packages
  * `upload_deb PKG=<package_name>` for uploading a single package using `debrelease`
  * `upload` for uploading all packages
  * `du` as a short alias for building and uploading all packages

When you build a package, `ver_mgmt.mk` checks main and slave repositories for following:
  * all repositories have the same version branch checked out
  * every repository is up-to-date with origin
  * there are no uncommited changes

The version of created deb package is concatenation of `VER` from `make bump` and total number of commits since `bump` in all related repositories, e.g. `1.4-12`. Thus any change you make to your project is forced to be commited and increments package version.
