#!/usr/bin/env ruby

require 'socket'

# TODO: make these much larger, see if we're effectively batching
# even if we don't mean to...
QUERY_TEXT = "STATUS".freeze
RESPONSE_TEXT = "OK".freeze

if ARGV.size != 2
  STDERR.puts "Usage: ./thread_test <num_workers> <num_requests>"
  exit 1
end

NUM_WORKERS = ARGV[0].to_i
NUM_REQUESTS = ARGV[1].to_i

worker_read = []
worker_write = []

master_read = []
master_write = []

writable_idx_for = {}
readable_idx_for = {}

workers = []
masters = []

puts "Setting up pipes..."
NUM_WORKERS.times do |i|
  r, w = IO.pipe
  worker_read.push r
  master_write.push w
  writable_idx_for[w] = i

  r, w = IO.pipe
  worker_write.push w
  master_read.push r
  readable_idx_for[r] = i
end

puts "Setting up threads..."
NUM_WORKERS.times do |i|
  t = Thread.new do
    # Worker code
    NUM_REQUESTS.times do |req_num|
      q = worker_read[i].read(QUERY_TEXT.size)
      if q != QUERY_TEXT
        raise "Fail! Expected #{QUERY_TEXT.inspect} but got #{q.inspect} on request #{req_num.inspect}!"
      end
      worker_write[i].print(RESPONSE_TEXT)
    end
  end
  workers.push t
end

### Master code ###

puts "Starting master..."

pending_msgs = NUM_WORKERS * NUM_REQUESTS

NUM_WORKERS.times do |worker_idx|
  # Start a 'master' thread for each worker thread
  mt = Thread.new do
    NUM_REQUESTS.times do |req_index|
      master_write[worker_idx].print QUERY_TEXT
      msg = master_read[worker_idx].read(RESPONSE_TEXT.size)
      if msg == RESPONSE_TEXT
        pending_msgs -= 1
      else
        STDERR.puts "Wrong response from worker! Got #{buf.inspect} instead of #{RESPONSE_TEXT.inspect}!"
      end
    end
  end
  masters.push mt
end

puts "Done, waiting for workers..."
workers.each { |t| t.join }
puts "Done, waiting for master threads..."
masters.each { |t| t.join }
puts "Done."

if pending_msgs != 0
  puts "Not all messages were delivered!"
  puts "Remaining messages: #{pending_msgs.inspect}"
  exit -1
else
  puts "All messages delivered successfully..."
  exit 0
end

# Exit
