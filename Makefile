test:
	crystal run spec/*_spec.cr

run:
	crystal run server.cr

bench:
	crystal run --release bench/load.cr
	ruby bench/load.rb

all: test bench

.PHONY: test run bench all
