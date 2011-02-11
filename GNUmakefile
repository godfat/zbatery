all::
RSYNC_DEST := zbatery.bogomip.org:/srv/zbatery
rfproject := rainbows
rfpackage := zbatery
man-rdoc: man html
	$(MAKE) -C Documentation comparison.html
	for i in $(man1_rdoc); do echo > $$i; done
doc:: man-rdoc
include pkg.mk
ifneq ($(VERSION),)
release::
	$(RAKE) raa_update VERSION=$(VERSION)
	$(RAKE) publish_news VERSION=$(VERSION)
	$(RAKE) fm_update VERSION=$(VERSION)
endif

base_bins := zbatery
bins := $(addprefix bin/, $(base_bins))
man1_rdoc := $(addsuffix _1, $(base_bins))
man1_bins := $(addsuffix .1, $(base_bins))
man1_paths := $(addprefix man/man1/, $(man1_bins))
clean:
	-$(MAKE) -C Documentation clean

man html:
	$(MAKE) -C Documentation install-$@
pkg_extra += $(man1_paths)
doc::
	$(RM) $(man1_rdoc)

all:: test
test:
	$(MAKE) -C t
.PHONY: man html
