#!make
SHELL := /bin/bash

MAIN_ADOC_SRC := $(shell yq r metanorma.yml metanorma.source.files | cut -c 3-999)
ifeq ($(MAIN_ADOC_SRC),ll)
MAIN_ADOC_SRC := $(filter-out README.adoc, $(wildcard sources/*.adoc))
endif

# CSV_SRC := $(wildcard sources/data/*.csv)
CSV_SRC := sources/data/codes.csv

ALL_ADOC_SRC := $(ADOC_SRC) $(wildcard sources/sections*/*.adoc)
ALL_SRC      := $(ALL_ADOC_SRC) $(CSV_SRC)

DERIVED_ADOC   := $(patsubst %.csv,%.adoc,$(CSV_SRC))
ADOC_GENERATOR := scripts/split_codes.rb

FORMATS := $(shell yq r metanorma.yml metanorma.formats | tr -d '[:space:]' | tr -s '-' ' ')
ifeq ($(FORMATS),null)
FORMAT_MARKER := mn-output-
FORMATS := $(shell grep "$(FORMAT_MARKER)" $(MAIN_ADOC_SRC) | cut -f 2 -d ' ' | tr ',' '\n' | sort | uniq | tr '\n' ' ')
endif

INPUT_XML   := $(patsubst %.adoc,%.xml,$(MAIN_ADOC_SRC))
OUTPUT_XML  := $(patsubst sources/%,documents/%,$(patsubst %.adoc,%.xml,$(MAIN_ADOC_SRC)))
OUTPUT_HTML := $(patsubst %.xml,%.html,$(OUTPUT_XML))

ifdef METANORMA_DOCKER
  PREFIX_CMD := echo "Running via docker..."; docker run -v "$$(pwd)":/metanorma/ $(METANORMA_DOCKER)

else
  PREFIX_CMD := echo "Running locally..."; bundle exec
endif

_OUT_FILES := $(foreach FORMAT,$(FORMATS),$(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))
OUT_FILES  := $(foreach F,$(_OUT_FILES),$($F))

all: documents.html

documents:
	mkdir -p $@

documents/%.xml: sources/%.xml | documents
	export GLOBIGNORE=sources/$*.adoc; \
	mv sources/$(addsuffix .*,$*) documents; \
	unset GLOBIGNORE

# Build canonical XML output
# If XML file is provided, copy it over
# Otherwise, build it using adoc
%.xml %.html: %.adoc $(ALL_ADOC_SRC) $(DERIVED_ADOC) | bundle
	BUILT_TARGET=$(shell yq r metanorma.yml metanorma.source.built_targets[$@]); \
	if [ "$$BUILT_TARGET" != "null" ]; then \
		if [ -f "$$BUILT_TARGET" ] && [ "$${BUILT_TARGET##*.}" == "xml" ]; then \
			cp "$$BUILT_TARGET" $@; \
		else \
			${PREFIX_CMD} metanorma $$BUILT_TARGET; \
			cp "$${BUILT_TARGET//adoc/xml}" $@; \
		fi; \
	else \
		${PREFIX_CMD} metanorma $<; \
	fi

# Build derivative output
sources/%.html sources/%.doc sources/%.pdf:	sources/%.xml
	BUILT_TYPE=$(shell yq r metanorma.yml metanorma.source.built_type[$<]); \
	if [ "$$BUILT_TYPE" != "null" ]; then \
		${PREFIX_CMD} metanorma -t $$BUILT_TYPE $<; \
	else \
		${PREFIX_CMD} metanorma $<; \
	fi

sources/data/codes.adoc: sources/data/codes.csv $(ADOC_GENERATOR)
	scripts/split_codes.rb $< $@

documents.rxl: $(OUTPUT_XML)
	${PREFIX_CMD} relaton concatenate \
	  -t "$(shell yq r metanorma.yml relaton.collection.name)" \
		-g "$(shell yq r metanorma.yml relaton.collection.organization)" \
		documents $@

documents.html: documents.rxl
	${PREFIX_CMD} relaton xml2html documents.rxl

define FORMAT_TASKS
OUT_FILES-$(FORMAT) := $($(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))

open-$(FORMAT):
	open $$(OUT_FILES-$(FORMAT))

clean-$(FORMAT):
	rm -f $$(OUT_FILES-$(FORMAT))

$(FORMAT): clean-$(FORMAT) $$(OUT_FILES-$(FORMAT))

.PHONY: clean-$(FORMAT)

endef

$(foreach FORMAT,$(FORMATS),$(eval $(FORMAT_TASKS)))

open: open-html

clean:
	rm -rf documents documents.{html,rxl} published *_images $(OUT_FILES)

bundle:
	if [ "x" == "${METANORMA_DOCKER}x" ]; then bundle; fi

.PHONY: bundle all open clean

#
# Watch-related jobs
#

.PHONY: watch serve watch-serve

NODE_BINS          := onchange live-serve run-p
NODE_BIN_DIR       := node_modules/.bin
NODE_PACKAGE_PATHS := $(foreach PACKAGE_NAME,$(NODE_BINS),$(NODE_BIN_DIR)/$(PACKAGE_NAME))

$(NODE_PACKAGE_PATHS): package.json
	npm i

watch: $(NODE_BIN_DIR)/onchange
	make all
	$< $(ALL_SRC) -- make all

define WATCH_TASKS
watch-$(FORMAT): $(NODE_BIN_DIR)/onchange
	make $(FORMAT)
	$$< $$(SRC_$(FORMAT)) -- make $(FORMAT)

.PHONY: watch-$(FORMAT)
endef

$(foreach FORMAT,$(FORMATS),$(eval $(WATCH_TASKS)))

serve: $(NODE_BIN_DIR)/live-server revealjs-css reveal.js
	export PORT=$${PORT:-8123} ; \
	port=$${PORT} ; \
	for html in $(HTML); do \
		$< --entry-file=$$html --port=$${port} --ignore="*.html,*.xml,Makefile,Gemfile.*,package.*.json" --wait=1000 & \
		port=$$(( port++ )) ;\
	done

watch-serve: $(NODE_BIN_DIR)/run-p
	$< watch serve

#
# Deploy jobs
#

publish: published

published: documents.html
	mkdir -p $@ && \
	cp -a documents $@/ && \
	cp $< $@/index.html;
