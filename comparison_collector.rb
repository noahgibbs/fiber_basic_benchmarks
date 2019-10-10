#!/usr/bin/env ruby

# This is basically using Ruby as a shellscript to run the various benchmarks and collect data about them.

# Each configuration is a number of workers and a number of requests per batch.
# A worker (thread, process, fiber) will run for one batch and then terminate. So small batches test
# worker startup/shutdown time, while larger batches test the time to hand off a message between
# different concurrency setups - threads and fibers might well have an advantage over
# processes for message I/O effiency, for instance.

REPS_PER_CONFIG = 10

## Worker configs from original benchmarking results post
#WORKER_CONFIGS = [
#    [ 5, 20_000],
#    [ 10, 10_000],
#    [ 100, 1000],
#    [ 1_000, 100],
#]

# Try 10x messages
WORKER_CONFIGS = [
    [ 5,   200_000],
    [ 10,  100_000],
    [ 100,  10_000],
    [ 1_000, 1_000],
]

BENCHMARKS = [
    # Older 'basic' tests similar to first two blog posts
    "fiber_test.rb",
    "fork_test.rb",
    "thread_test.rb",

    # Variants to compare against
    "thread_test_multi_master.rb",
    "williams_fiber_test.rb",
]

# Ruby will generally spawn subshells to run the benchmarks - this permits using RVM to change
# the Ruby version. By setting up this array, you can change the conditions under which Ruby
# runs the benchmark.
#SHELL_PREAMBLES = [
#    "rvm use 2.0.0-p0",
#    "rvm use 2.1.10",
#    "rvm use 2.2.10",
#    "rvm use 2.3.8",
#    "rvm use 2.4.5",
#    "rvm use 2.5.3",
#    "rvm use 2.6.3",
#    "rvm use ruby-head",
#]

RUBY_VERSIONS = [ "2.0.0-p0", "2.1.10", "2.2.10", "2.3.8", "2.4.5", "2.5.3", "2.6.5" ]
SHELL_PREAMBLES = RUBY_VERSIONS.map { |ver|
    [
        "ulimit -Sn 1024",  # Linux has tight default file descriptor limits
        "rvm use #{ver} --install",
        "gem install bundler -v1.17.3",
        "bundle",
    ].join("&&")
}

# Before we spawn this subshell and run the test - should we?
RUBY_PREFLIGHT = lambda do |preamble, bench, workers, messages|
  return false if preamble == "rvm use 2.0.0-p0" && workers > 100  # Ruby 2.0.0 segfaults with too many procs, fibers or threads
  true
end

COLLECTOR_TS = Time.now.to_i

require "json"

data_filename = "collector_data_#{COLLECTOR_TS}.json"
out_data = {
    collector_ruby_version: RUBY_VERSION,
    reps_per_config: REPS_PER_CONFIG,
    configs: WORKER_CONFIGS,
    benchmarks: BENCHMARKS,
    preambles: SHELL_PREAMBLES,
    summary: {},
    results: [],
}

# Generate all configurations
configs_w_preamble =
(0...REPS_PER_CONFIG).flat_map { |rep|
    SHELL_PREAMBLES.flat_map { |preamble|
        BENCHMARKS.flat_map { |bench|
            WORKER_CONFIGS.map { |c| [rep, preamble, bench] + c }
        }
    }
}

#puts "All configs:\n#{JSON.pretty_generate configs_w_preamble}"

# Randomize the order of trials
ordered_configs = configs_w_preamble.sample(configs_w_preamble.size)

successes = 0
failures = 0
skips = 0
no_data = 0

run_data_file = "/tmp/ruby_fiber_collector_#{COLLECTOR_TS}_subconfig.json"

ordered_configs.each do |config|
  rep_num, preamble, bench, workers, messages = *config

  should_run = RUBY_PREFLIGHT.call(preamble, bench, workers, messages)
  if should_run
    File.unlink(run_data_file) if File.exist?(run_data_file)
    shell_command = "bash -l -c \"#{preamble} && benchmarks/#{bench} #{workers} #{messages} #{run_data_file}\""
    shell_t0 = Time.now
    #puts "Running with config: #{rep_num.inspect} #{preamble.inspect} #{bench.inspect} #{workers.inspect} #{messages.inspect}..."
    puts "Running command: #{shell_command.inspect}"
    result = system(shell_command)
    shell_tfinal = Time.now
    shell_elapsed = shell_tfinal - shell_t0

    data_present = File.exist? run_data_file
    run_data = {
        rep_num: rep_num,
        preamble: preamble,
        benchmark: bench,
        workers: workers,
        messages: messages,
        result_status: result,
        whole_process_time: shell_elapsed,
    }

    if result && data_present
      puts "Success..."
      successes += 1
    elsif result
      puts "Success with no data..."
      no_data += 1
    elsif data_present
      puts "This really shouldn't happen! Outfile: #{run_data_file}"
      raise "Data file written but subprocess failed!"
    else
      puts "Failure..."
      failures += 1
    end

    if data_present
      run_data[:result_data] = JSON.load(File.read run_data_file)
    else
      run_data[:result_data] = nil
    end
    out_data[:results].push run_data
  else
    puts "Skipping #{preamble.inspect} #{bench.inspect} #{workers.inspect} #{messages.inspect}..."
    skips += 1
  end
end

if ordered_configs.size != successes + failures + skips + no_data
    puts "Error in collector bookkeeping! #{ordered_configs.size} total configurations, but: successes: #{successes}, failures: #{failures}, no data: #{no_data}, skips: #{skips}"
end

out_data[:summary] = {
    successes: successes,
    failures: failures,
    skips: skips,
    no_data: no_data,
    total_configs: ordered_configs.size,
}

File.open(data_filename, "w") do |f|
    f.write JSON.pretty_generate(out_data)
end
puts "#{successes}/#{successes + failures + skips} returned success from subshell, with #{skips} skipped and #{failures} failures."
puts "Finished data collection, written to #{data_filename}"
