# This is basically using Ruby as a shellscript to run the various benchmarks and collect data about them.

# Each configuration is a number of workers and a number of requests per batch.
# A worker (thread, process, fiber) will run for one batch and then terminate. So small batches test
# worker startup/shutdown time, while larger batches test the time to hand off a message between
# different concurrency setups - threads and fibers might well have an advantage over
# processes for message I/O effiency, for instance.

WORKER_CONFIGS = [
    [ 10, 1_000],
    [ 100, 100],
    [ 1_000, 10],
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
SHELL_PREAMBLES = [
    "rvm use 2.0.0-p0",
    "rvm use 2.1.10",
    "rvm use 2.2.10",
    "rvm use 2.3.8",
    "rvm use 2.4.5",
    "rvm use 2.5.3",
    "rvm use 2.6.3",
    "rvm use ruby-head",
]

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
    configs: WORKER_CONFIGS,
    benchmarks: BENCHMARKS,
    preambles: SHELL_PREAMBLES,
    summary: {},
    results: [],
}

configs_w_preamble = SHELL_PREAMBLES.flat_map { |preamble|
    BENCHMARKS.flat_map { |bench|
        WORKER_CONFIGS.map { |c| [preamble, bench] + c }
    }
}

puts "All configs:\n#{JSON.pretty_generate configs_w_preamble}"

# Randomize the order of trials
ordered_configs = configs_w_preamble.sample(configs_w_preamble.size)

successes = 0
failures = 0
skips = 0

ordered_configs.each do |config|
  preamble, bench, workers, messages = *config

  should_run = RUBY_PREFLIGHT.call(preamble, bench, workers, messages)
  if should_run
    run_data_file = "/tmp/ruby_fiber_collector_#{COLLECTOR_TS}_subconfig.json"
    shell_command = "bash -c \"#{preamble} && benchmarks/fiber_test.rb #{workers} #{messages} #{run_data_file}\""
    shell_t0 = Time.now
    result = system(shell_command)
    shell_tfinal = Time.now

    data_present = File.exist? run_data_file

    if result && data_present
      successes += 1
    elsif result
      no_data += 1
    else
      failures += 1
    end

    shell_elapsed = shell_tfinal - shell_t0
    out_data[:results].push result
  else
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
    no_data: nodata,
    total_configs: ordered_configs.size,
}

File.open(data_filename, "w") do |f|
    JSON.pretty_generate(out_data)
end
puts "#{successes}/#{successes + failures + skips} returned success from subshell, with #{skips} skipped and #{failures} failures."
puts "Finished data collection, written to #{data_filename}"
