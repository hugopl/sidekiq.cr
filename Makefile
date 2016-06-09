test:
	crystal spec

run:
	crystal run bin/sidekiq.cr

bench:
	crystal run --release bench/load.cr
	ruby bench/load.rb

bin: clean
	time crystal build --release -o sidekiq bin/sidekiq.cr
	time crystal build --release -o sideweb bin/web.cr

clean:
	rm -f bin/sidekiq bin/sideweb

all: test bin bench

.PHONY: test run bench all bin clean
