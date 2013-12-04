##
## - WARNING -
##
## Do not edit this file if possible.
## project.mk is meant to be common for all services.
## It's better to change Makefile instead.
## If you really need to change this file, consider
## making the change generic and update the file in
## rebar-templates as well:
## https://github.com/EchoTeam/rebar-templates/blob/master/service_project.mk
##

.PHONY: all compile test clean target generate rel
.PHONY: update-lock get-deps update-deps
.PHONY: run run-no-sync upgrade dev-generate dev-target

REBAR_BIN := $(abspath ./)/rel/../rebar # "rel/../" is a workaround for rebar bug
ifeq ($(wildcard $(REBAR_BIN)),)
	REBAR_BIN := $(shell which rebar)
endif
REBAR_FREEDOM := $(REBAR_BIN) -C rebar.config
REBAR_LOCKED  := $(REBAR_BIN) -C rebar.config.lock skip_deps=true
REBAR := $(REBAR_FREEDOM)

DEFAULT_OVERLAY_VARS := vars/vars.default.config
DEV_OVERLAY_VARS     := vars/vars.dev.config
DEFAULT_TARGET_DIR   := $(SERVICE_NAME)

all: compile

compile: update-deps
	$(eval ROOT_APP_NAME := $(shell ./bin/appname.erl))
	# Making plugins available first:
	$(REBAR) compile apps=$(ROOT_APP_NAME),lager,echo_rebar_plugins
	$(REBAR) compile
	
update-lock:
ifdef apps
	$(eval apps_list = $(shell echo $(apps) | sed 's/,/ /g'))
	@echo "Updating rebar.config.lock for $(apps)..."
	@for app in $(apps_list); do \
		rmcmd="rm -rI ./deps/$$app"; \
		echo "WARNING: Make sure you don't have code left to push in ./deps/$$app directory."; \
		echo $$rmcmd; \
		echo `[ -d ./deps/$$app ] && $$rmcmd`; \
	done
	$(REBAR) get-deps
else
	$(REBAR) update-deps
endif
	$(eval ROOT_APP_NAME := $(shell ./bin/appname.erl))
	# Making lock-deps available first:
	$(REBAR) compile
	$(REBAR) lock-deps skip_deps=true keep_first=lager,echo_rebar_plugins
	@touch deps/.updated

get-deps:
	$(REBAR_LOCKED) get-deps

update-deps: deps/.updated

deps/.updated: rebar.config.lock
	$(REBAR_LOCKED) update-deps ignore_deps=true
	@touch deps/.updated

rel:
	$(MAKE) -C rel

generate: update-deps compile rel
	$(eval relvsn := $(shell bin/relvsn.erl))
	$(eval overlay_vars ?= $(DEFAULT_OVERLAY_VARS))
	$(eval target_dir   ?= $(DEFAULT_TARGET_DIR))
	cd rel && $(REBAR_BIN) generate -f overlay_vars=$(overlay_vars) target_dir=$(target_dir)
	cp rel/$(target_dir)/releases/$(relvsn)/$(SERVICE_NAME).boot rel/$(target_dir)/releases/$(relvsn)/start.boot #workaround for rebar bug
	echo $(relvsn) > rel/$(target_dir)/relvsn

clean:
	$(REBAR) clean
	rm -rf rel/$(SERVICE_NAME)*

test:
	$(REBAR) eunit skip_deps=meck,lager

# Make target system for production
# Invoked by otp-release-scripts
target: clean generate


######################################
## All targets below are for use    ##
## in development environment only. ##
######################################

dev-generate:
	$(eval target_dir ?= $(DEFAULT_TARGET_DIR))
	$(MAKE) generate overlay_vars=$(DEV_OVERLAY_VARS) target_dir=$(target_dir)

dev-target: clean dev-generate

# Generates upgrade upon what is currently in rel/$(DEFAULT_TARGET_DIR)
upgrade: rel
	$(eval cur_vsn := $(shell cat rel/$(DEFAULT_TARGET_DIR)/relvsn))
	$(eval new_vsn  := $(shell bin/relvsn.erl))
	$(eval new_target_dir := $(SERVICE_NAME)_$(new_vsn))
	@[ -n "$(cur_vsn)" ] || (echo "Run 'make dev-target' first" && exit 1)
	-rm -rf rel/$(new_target_dir)
	$(MAKE) dev-generate target_dir=$(new_target_dir)
	cd rel && $(REBAR_BIN) generate-upgrade target_dir=$(new_target_dir) previous_release=$(DEFAULT_TARGET_DIR)
	mv rel/$(new_target_dir).tar.gz rel/$(DEFAULT_TARGET_DIR)/releases/
	./rel/$(DEFAULT_TARGET_DIR)/bin/$(SERVICE_NAME) upgrade $(new_target_dir)

downgrade:
	$(eval cur_vsn := $(shell bin/relvsn.erl))
	$(eval old_vsn := $(shell cat rel/$(DEFAULT_TARGET_DIR)/relvsn))
	./rel/$(DEFAULT_TARGET_DIR)/bin/$(SERVICE_NAME) remove_release $(cur_vsn) $(old_vsn)

# Runs the service
run: dev-generate
	./rel/$(DEFAULT_TARGET_DIR)/bin/$(SERVICE_NAME) console -s sync

run-no-sync: dev-generate
	./rel/$(DEFAULT_TARGET_DIR)/bin/$(SERVICE_NAME) console