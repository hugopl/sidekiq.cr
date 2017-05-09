test:
	crystal spec

prepare:
	shards

web:
	crystal run examples/web.cr

run:
	crystal run examples/sidekiq.cr

profile:
	crystal build bench/load.cr
# use `instruments -s` to find out your device name
	instruments -w MikeMBP -t "Time Profiler" ./load

bench:
	crystal build --release bench/load.cr && ./load
	#crystal run --release bench/load.cr
	#ruby bench/load.rb

bin: clean
	time crystal build -s --release -o sidekiq examples/sidekiq.cr
	time crystal build -s --release -o sideweb examples/web.cr

clean:
	rm -f sidekiq sideweb

fixtures:
	cd spec/fixtures && ruby create_fixtures.rb

tag:
	git tag `crystal eval 'require "./src/sidekiq.cr"; puts "v#{Sidekiq::VERSION}"'`

release: test bin tag

all: test bin bench

.PHONY: test run bench all bin clean fixtures
