#!/usr/bin/env ruby

require 'socket'

# TODO: make these much larger, see if we're effectively batching
# even if we don't mean to...
QUERY_TEXT = "STATUS".freeze
RESPONSE_TEXT = "OK".freeze

if ARGV.size != 2
  STDERR.puts "Usage: ./fork_test <num_workers> <num_requests>"
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

puts "Setting up processes..."
NUM_WORKERS.times do |i|
  pid = fork do
    # Worker code
    NUM_REQUESTS.times do |req_num|
      q = worker_read[i].read(QUERY_TEXT.size)
      if q != QUERY_TEXT
        raise "Fail! Expected #{QUERY_TEXT.inspect} but got #{q.inspect} on request #{req_num.inspect}!"
      end
      worker_write[i].print(RESPONSE_TEXT)
    end
  end
  workers.push pid
end

### Master code ###

pending_write_msgs = (1..NUM_WORKERS).map { NUM_REQUESTS }
pending_read_msgs = pending_write_msgs.dup

puts "Starting master..."
loop do
  break if master_read.empty? && master_write.empty?
  readable, writable = IO.select master_read, master_write, []

  # Receive responses
  readable.each do |io|
    idx = readable_idx_for[io]

    buf = io.read(RESPONSE_TEXT.size)
    if buf != RESPONSE_TEXT
      master_read.delete(io)
      STDERR.puts "Wrong response from worker! Got #{buf.inspect} instead of #{RESPONSE_TEXT.inspect}!"
    else
      pending_read_msgs[idx] -= 1
      if pending_read_msgs[idx] == 0
        # This changes the indexing of master_read, so it
        # must never be indexed by number. But we don't want
        # to keep seeing it as readable on every select call...
        master_read.delete(io)
      end
    end
  end

  # Send new messages
  writable.each do |io|
    idx = writable_idx_for[io]
    io.print QUERY_TEXT
    pending_write_msgs[idx] -= 1
    if pending_write_msgs[idx] == 0
      # This changes the indexing of master_write, so it
      # must never be indexed by number. But we don't want
      # to keep seeing it as writable on every select call...
      master_write.delete(io)
    end
  end
end

puts "Done, waiting for workers..."
workers.each { |pid| Process.waitpid(pid) }
puts "Done."

if pending_write_msgs.any? { |p| p != 0 } || pending_read_msgs.any? { |p| p != 0}
  puts "Not all messages were delivered!"
  puts "Remaining read: #{pending_read_msgs.inspect}"
  puts "Remaining write: #{pending_write_msgs.inspect}"
  exit -1
else
  puts "All messages delivered successfully..."
  exit 0
end

# Exit
