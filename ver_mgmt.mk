# Where to fork a new branch
AT = master
# Branch prefix
BRPR = release-
BRANCH = $(BRPR)$(VER)
COMMITMSG = "$(VER) branch start"
# Helpers to decide if we want to create a new branch
HAVELOCALBRANCH = $(shell git branch | grep " $(BRANCH)")
HAVEREMOTEBRANCH = $(shell git branch -r | grep " origin/$(BRANCH)")

APPSRC = src/$(PROJECT).app.src
DebDir = pkg/$(PROJECT)/debian
DebChLog = $(DebDir)/changelog

.PHONY: ensure_slave_deps
define ensure_dep # (DepName)
	@test -f deps/$(1)/ebin/$(1).app || $(MAKE) deps

endef
ensure_slave_deps:
	$(foreach dep,$(SLAVE_DEPS),$(call ensure_dep,$(dep)))

.PHONY: bump local_bump deps_bump
# Bump local and deps versions
bump: local_bump deps_bump


# Create a new branch at specified point
define fork_branch
	$(info Creating branch $(1) at $(AT))
	git checkout -b "$(1)" "$(AT)"
endef

define bump_makefile_dep # (DepName)
	sed -i.orig '/^dep_$(1) / s|master$$|$(BRANCH)|' Makefile && rm Makefile.orig

endef

# Bump project version
local_bump:
ifndef VER
	$(error VER undefined)
endif
ifeq ($(HAVELOCALBRANCH), )
  ifeq ($(HAVEREMOTEBRANCH), )
	$(info ======= No local branch and no remote branch)
	# Create version branch
	$(call fork_branch,"$(BRANCH)")
	# Edit *.app.src version
	sed -i.orig 's|{vsn,[^}]*}|{vsn, "'$(VER)'"}|' $(APPSRC) && rm $(APPSRC).orig
	# Edit relx.config version when there is one
	test -f relx.config && { sed -i.orig 's|\({release,[[:space:]]*{[^},]*,\)[^}]*}|\1 "'$(VER)'"}|' relx.config && rm relx.config.orig; } || true
	# Update own dependencies in Makefile
	$(foreach dep,$(SLAVE_DEPS),$(call bump_makefile_dep,$(dep)))
	# Push the new branch to the upstream
	git add $(APPSRC)
	test -f relx.config && git add relx.config || true
	git add Makefile
	git commit -m $(COMMITMSG)
	git push -u origin "$(BRANCH)"
  else # HAVEREMOTEBRANCH
	$(info ======= No local branch, but remote branch exists)
	git checkout -b "$(BRANCH)" "origin/$(BRANCH)"
  endif # HAVEREMOTEBRANCH
else # HAVELOCALBRANCH
	$(info ======= Local branch exists)
	git checkout "$(BRANCH)"
	git push -u origin "$(BRANCH)"
endif


define dep_make_inline # (DepName, Args)
	echo "include Makefile $(CURDIR)/ver_mgmt.mk" | $(MAKE) -f - -C deps/$(1) $(2)
endef

define dep_make # (DepName, Args)
	+echo "include Makefile $(CURDIR)/ver_mgmt.mk" | $(MAKE) -f - -C deps/$(1) $(2)
	# Newline is required to split substitutions into separate rules, do not remove it

endef
	
define dep_bump # (DepName)
	$(call dep_make,$(1),local_bump VER="$(VER)")
endef
deps_bump: ensure_slave_deps
	$(foreach dep,$(SLAVE_DEPS),$(call dep_bump,$(dep)))


# Restore fork point by commit message on app.src
CURRENTVER = $(shell git symbolic-ref HEAD | sed -n 's|^.*/$(BRPR)||p')
BRANCHSTART = $(shell git log --grep=$(COMMITMSG) --fixed-strings --format=format:%H -1 $(APPSRC))

.PHONY: commits local_commits

# Get commits since version branch creation
local_commits:
ifeq ($(CURRENTVER), )
	$(error Cannot determine current version. Check your branch!)
endif
	$(eval VER := $(CURRENTVER))
ifeq ($(BRANCHSTART), )
	$(error Cannot find branch start.)
endif
	git log --pretty=format:"%at $(PROJECT): %t %s%x09 -- %an <%ae>  %aD%n" $(BRANCHSTART)..HEAD

define dep_commits # (DepName)
	$(call dep_make_inline,$(1),-s local_commits VER="$(VER)")
endef
commits:
ifeq ($(CURRENTVER), )
	$(error Cannot determine current version. Check your branch!)
endif
	+bash -c '{ $(MAKE) -s local_commits; $(foreach dep,$(SLAVE_DEPS), $(call dep_commits,$(dep));)} | grep -v "^$$" | sort -n -k2 | cut -d" " -f2-'


.PHONY: changelog
define pkg_changelog # (Name, DebRoot)
	+rm -f $(2)/changelog
	+COMMITS=`$(MAKE) --no-print-directory -s commits`; BUILD=`echo "$$COMMITS" | grep -cv "^$$"`; \
		dch --create --changelog $(2)/changelog --package $(1) --newversion $(CURRENTVER)-$$BUILD "Start version $(CURRENTVER)"; \
		echo "$$COMMITS" | xargs -n1 -d"\n" dch --changelog $(2)/changelog --append
	+dch --changelog $(2)/changelog --release ""

endef
PKGDEBROOTS = $(wildcard pkg/*/debian)
changelog: ensure_slave_deps
ifeq ($(CURRENTVER), )
	$(error Cannot determine current version. Check your branch!)
endif
	$(foreach PKGDEBROOT,$(PKGDEBROOTS), $(call pkg_changelog,$(patsubst pkg/%/debian,%,$(PKGDEBROOT)),$(PKGDEBROOT)))


.PHONY: local_check_source check_source
local_check_source:
ifndef VER
	$(error VER undefined)
else
ifneq "$(VER)" "$(CURRENTVER)"
	$(error $(PROJECT): Active version is $(CURRENTVER) while $(VER) expected)
else # VER == CURRENTVER
	git fetch # ensure we have actual state of remote
ifneq "$(shell git rev-parse $(BRANCH))" "$(shell git rev-parse origin/$(BRANCH))"
	$(error $(PROJECT): Local and remote $(BRANCH) heads differ)
endif
ifneq "$(shell git diff)" ""
	$(error $(PROJECT): There are unstaged modifications)
endif
ifneq "$(shell git diff --cached)" ""
	$(error $(PROJECT): There are staged changes uncommited)
endif
	@true
endif # VER vs CURRENTVER
endif # VER

deps_check_source:
	$(foreach dep,$(SLAVE_DEPS),$(call dep_make,$(dep),local_check_source VER=$(VER)))

check_source: ensure_slave_deps
ifeq ($(CURRENTVER), )
	$(error Cannot determine current version. Check your branch!)
endif
	+$(MAKE) local_check_source deps_check_source VER=$(CURRENTVER)


.PHONY: build_deb upload_deb deb upload du
build_deb:
ifndef PKG
	$(error PKG undefined. Possible PKGs: $(foreach PKGDEBROOT,$(PKGDEBROOTS), $(patsubst pkg/%/debian,%,$(PKGDEBROOT))) )
endif
	rm -rf pkg/$(PKG)_*.{build,changes,deb,upload,dsc,tar.gz}
	cd pkg/$(PKG) && debuild --no-tgz-check -i -b

define build_deb # (PKG)
	+$(MAKE) build_deb PKG=$(1)

endef
deb: check_source changelog clean all
	$(foreach PKGDEBROOT,$(PKGDEBROOTS), $(call build_deb,$(patsubst pkg/%/debian,%,$(PKGDEBROOT))))


upload_deb:
ifndef PKG
	$(error PKG undefined. Possible PKGs: $(foreach PKGDEBROOT,$(PKGDEBROOTS), $(patsubst pkg/%/debian,%,$(PKGDEBROOT))) )
endif
	cd pkg/$(PKG) && debrelease --no-conf --configfile dupload.conf

define upload_deb # (PKG)
	$(MAKE) upload_deb PKG=$(1)

endef
upload:
	$(foreach PKGDEBROOT,$(PKGDEBROOTS), $(call upload_deb,$(patsubst pkg/%/debian,%,$(PKGDEBROOT))))


du:
	$(MAKE) deb
	$(MAKE) upload
