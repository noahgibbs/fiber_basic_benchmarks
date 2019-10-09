#!/usr/bin/env ruby

# Analyze results from comparison_collector runs

require 'json'

if ARGV.size != 1
    raise "You must supply exactly one argument: the collector data to analyze!"
end

input_data = JSON.load File.read(ARGV[0])

by_pre_bench_workers_msgs = {}

input_data["results"].each do |result|
    by_pre_bench_workers_msgs[result["preamble"]] ||= {}
    by_pre_bench_workers_msgs[result["preamble"]][result["benchmark"]] ||= {}
    by_pre_bench_workers_msgs[result["preamble"]][result["benchmark"]][result["workers"]] ||= {}
    by_pre_bench_workers_msgs[result["preamble"]][result["benchmark"]][result["workers"]][result["messages"]] ||= []

    # Disqualify failed or no-data results
    if result["result_status"] && result["result_data"] && result["result_data"]["success"]
        by_pre_bench_workers_msgs[result["preamble"]][result["benchmark"]][result["workers"]][result["messages"]].push result
    end
end

def percentile(list, pct)
  len = list.length
  how_far = pct * 0.01 * (len - 1)
  prev_item = how_far.to_i
  return list[prev_item] if prev_item >= len - 1
  return list[0] if prev_item < 0

  linear_combination = how_far - prev_item
  list[prev_item] + (list[prev_item + 1] - list[prev_item]) * linear_combination
end

def array_mean(arr)
  return nil if arr.empty?
  arr.inject(0.0, &:+) / arr.size
end

# Calculate variance based on the Wikipedia article of algorithms for variance.
# https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
# Includes Bessel's correction.
def array_variance(arr)
  n = arr.size
  return nil if arr.empty? || n < 2

  ex = ex2 = 0.0
  arr0 = arr[0].to_f
  arr.each do |x|
    diff = x - arr0
    ex += diff
    ex2 += diff * diff
  end

  (ex2 - (ex * ex) / arr.size) / (arr.size - 1)
end

by_pre_bench_workers_msgs.each do |preamble, pre_hash|
    pre_hash.each do |benchmark, bench_hash|
        bench_hash.each do |workers, workers_hash|
            workers_hash.each do |msgs, data_array|
                config_description = "Pre: #{preamble.inspect} Bench: #{benchmark.inspect} W: #{workers.inspect} Msg: #{msgs.inspect}"
                if data_array.empty?
                    puts "No data for configuration #{config_description}"
                    workers_hash.delete(msgs)
                else
                    whole_process_data = data_array.map { |result| result["whole_process_time"] }
                    working_data = data_array.map { |result| result["result_data"]["time"] }
                    puts "Messages-only data for configuration #{config_description}:"
                    puts "  mean:     #{array_mean(working_data)}"
                    puts "  median:   #{percentile(working_data, 50)}"
                    puts "  variance: #{array_variance(working_data)}"
                    puts "  std_dev:  #{Math.sqrt array_variance(working_data)}"
                    puts "-----"
                    puts "Whole-process data for configuration #{config_description}:"
                    puts "  mean:     #{array_mean(whole_process_data)}"
                    puts "  median:   #{percentile(whole_process_data, 50)}"
                    puts "  variance: #{array_variance(whole_process_data)}"
                    puts "  std_dev:  #{Math.sqrt array_variance(whole_process_data)}"
                    puts "-----"
                end
            end
        end
    end
end
