#!make
SHELL := /bin/bash

# Detect number of cores (e.g. for bundle install)
ifeq ($(OS),Windows_NT)
	CORES := $(shell nproc --all)
else
	UNAME_S := $(shell uname -s)

	ifeq ($(UNAME_S),Linux)
		CORES := $(shell grep -c '^$$' /proc/cpuinfo)
	endif

	ifeq ($(UNAME_S),Darwin)
		CORES := $(shell sysctl -n hw.ncpu)
	endif

	ifeq ($(UNAME_S),FreeBSD)
		CORES := $(shell sysctl -n hw.ncpu)
	endif
endif

SRC := $(filter-out README.adoc, $(wildcard sources/*.adoc))

OTHER_ADOC_SRC := $(wildcard sources/sections*/*.adoc)

LUTAML_SRC  := $(wildcard sources/models/*.lutaml)
DERIVED_PNG := $(patsubst sources/models/%.lutaml,sources/images/%.png,$(LUTAML_SRC))

DERIVED_SRC := $(DERIVED_PNG)

SUPPLEMENTARY_SRC := $(OTHER_ADOC_SRC) $(DERIVED_SRC)

OUT_DIR := site

define print_vars
	$(info "src $(SRC)")
	$(info "formats $(FORMATS)")
endef

.PHONY: all
all: documents.html debug

.PHONY: prep
prep:
	bundle install

.PHONY: debug
debug:
	$(call print_vars)

sources/images/%.png: sources/models/%.lutaml
	bundle exec lutaml -t png -o $@ $<

documents:
	mkdir -p $@

documents.html: metanorma.yml $(SRC) $(SUPPLEMENTARY_SRC) | documents
	bundle exec metanorma site generate --agree-to-terms

.PHONY: open
open: open-html

.PHONY: clean
clean:
	rm -rf documents documents.{html,rxl} $(OUT_DIR) *_images $(DERIVED_SRC)

.PHONY: test
test:
	scripts/run_tests

#
# Deploy jobs
#

.PHONY: publish
publish: $(OUT_DIR)

$(OUT_DIR): documents.html
	mkdir -p $@ && \
	cp -a documents $@/ && \
	cp $< $@/index.html;