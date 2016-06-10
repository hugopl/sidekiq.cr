test:
	crystal spec

run:
	crystal run examples/sidekiq.cr

bench:
	crystal run --release bench/load.cr
	ruby bench/load.rb

bin: clean
	time crystal build --release -o sidekiq examples/sidekiq.cr
	time crystal build --release -o sideweb examples/web.cr

clean:
	rm -f sidekiq sideweb

all: test bin bench

.PHONY: test run bench all bin clean
