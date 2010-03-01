# we can run tests in parallel with GNU make

all::

pid := $(shell echo $$PPID)

RUBY = ruby
zbatery_lib := $(shell cd ../lib && pwd)
-include ../local.mk
ifeq ($(RUBY_VERSION),)
  RUBY_VERSION := $(shell $(RUBY) -e 'puts RUBY_VERSION')
endif

ifeq ($(RUBY_VERSION),)
  $(error unable to detect RUBY_VERSION)
endif

ifeq ($(RUBYLIB),)
  RUBYLIB := $(zbatery_lib)
else
  RUBYLIB := $(zbatery_lib):$(RUBYLIB)
endif
export RUBYLIB RUBY_VERSION

models += ThreadPool
models += ThreadSpawn
models += Rev
models += EventMachine
models += NeverBlock
models += RevThreadSpawn
models += RevThreadPool

rp := )
ONENINE := $(shell case $(RUBY_VERSION) in 1.9.*$(rp) echo true;;esac)
ifeq ($(ONENINE),true)
  models += Revactor
  models += FiberSpawn
  models += RevFiberSpawn
  models += FiberPool
endif
all_models := $(models) Base

T = $(wildcard t[0-9][0-9][0-9][0-9]-*.sh)

MODEL_T := $(foreach m,$(all_models),$(addprefix $(m).,$(T)))
$(T): MODELS = $(models)

# some tests can be run with all models
t0000-simple-http.sh: MODELS = $(all_models)
t0001-unix-http.sh: MODELS = $(all_models)
t0002-graceful.sh: MODELS = $(all_models)
t0002-parser-error.sh: MODELS = $(all_models)
t0003-reopen-logs.sh: MODELS = $(all_models)

# recursively run per-model tests
# haven't figured out a good way to make make non-recursive here, yet...
$(T):
	$(MAKE) $(foreach m,$(MODELS),$(addprefix $(m).,$@))

$(all_models):
	$(MAKE) $(filter $@.%,$(MODEL_T))

all:: $(T)

# can't rely on "set -o pipefail" since we don't require bash or ksh93 :<
t_pfx = trash/$@-$(RUBY_VERSION)
TEST_OPTS =
# TRACER = strace -f -o $(t_pfx).strace -s 100000
# TRACER = /usr/bin/time -o $(t_pfx).time

ifdef V
  ifeq ($(V),2)
    TEST_OPTS += --trace
  else
    TEST_OPTS += --verbose
  endif
endif

test-bin-$(RUBY_VERSION)/zbatery: ruby_bin = $(shell which $(RUBY))
test-bin-$(RUBY_VERSION)/zbatery: ../bin/zbatery
	mkdir -p $(@D)
	install -m 755 $^ $@.$(pid)
	$(RUBY) -i -p -e '$$_.gsub!(%r{^#!.*$$},"#!$(ruby_bin)")' $@.$(pid)
	mv $@.$(pid) $@

random_blob:
	dd if=/dev/urandom bs=1M count=30 of=$@.$(pid)
	mv $@.$(pid) $@

$(T): random_blob

dependencies := socat curl
deps := $(addprefix .dep+,$(dependencies))
$(deps): dep_bin = $(lastword $(subst +, ,$@))
$(deps):
	@which $(dep_bin) > $@.$(pid) 2>/dev/null || :
	@test -s $@.$(pid) || \
	  { echo >&2 "E '$(dep_bin)' not found in PATH=$(PATH)"; exit 1; }
	@mv $@.$(pid) $@
dep: $(deps)

$(MODEL_T): export model = $(firstword $(subst ., ,$@))
$(MODEL_T): script = $(subst $(model).,,$@)
$(MODEL_T): trash/.gitignore
$(MODEL_T): export RUBY := $(RUBY)
$(MODEL_T): export PATH := $(CURDIR)/test-bin-$(RUBY_VERSION):$(PATH)
$(MODEL_T): test-bin-$(RUBY_VERSION)/zbatery dep
	$(TRACER) $(SHELL) $(SH_TEST_OPTS) $(script) $(TEST_OPTS)

trash/.gitignore:
	mkdir -p $(@D)
	echo '*' > $@

clean:
	$(RM) -r trash/*.log trash/*.code test-bin-$(RUBY_VERSION)

.PHONY: $(T) clean
