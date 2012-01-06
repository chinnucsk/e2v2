TESTS=""

compile:
	./rebar compile

quick:
	./rebar compile skip_deps=true

.PHONY: test
test: compile
ifeq ($(TESTS), "")
	./rebar -j1 eunit
else
	./rebar -j1 eunit suite=$(TESTS)
endif

.PHONY: doc
doc:
	./rebar doc

clean:
	./rebar clean

shell:
	 erl -pa ebin
