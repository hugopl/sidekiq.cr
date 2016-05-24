test:
	crystal run spec/*_spec.cr

run:
	crystal run server.cr

bench:
	crystal run --release bench/load.cr
	ruby bench/load.rb

.PHONY: test run bench
