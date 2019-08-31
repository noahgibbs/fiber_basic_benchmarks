#!/usr/bin/env ruby

require 'socket'
require 'fiber'

# TODO: make these much larger, see if we're effectively batching
# even if we don't mean to...
QUERY_TEXT = "STATUS".freeze
RESPONSE_TEXT = "OK".freeze

if ARGV.size != 2
  STDERR.puts "Usage: ./fiber_test <num_workers> <num_requests>"
  exit 1
end

NUM_WORKERS = ARGV[0].to_i
NUM_REQUESTS = ARGV[1].to_i

# Fiber reactor code taken from
# https://www.codeotaku.com/journal/2018-11/fibers-are-the-right-solution/index
class Reactor
    def initialize
        @readable = {}
        @writable = {}
    end

    def run
        while @readable.any? or @writable.any?
            readable, writable = IO.select(@readable.keys, @writable.keys, [])

            readable.each do |io|
                @readable[io].resume
            end

            writable.each do |io|
                @writable[io].resume
            end
        end
    end

    def wait_readable(io)
        @readable[io] = Fiber.current
        Fiber.yield
        @readable.delete(io)

        return yield if block_given?
    end

    def wait_writable(io)
        @writable[io] = Fiber.current

        Fiber.yield

        @writable.delete(io)

        return yield if block_given?
    end
end

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

# For now, I'm going to run all the (Fiber-based) workers
# in a single thread, with the master in the main
# thread.
worker_thread = Thread.new do
  reactor = Reactor.new

  puts "Setting up fibers..."
  NUM_WORKERS.times do |i|
    f = Fiber.new do
      # Worker code
      NUM_REQUESTS.times do |req_num|
        q = reactor.wait_readable(worker_read[i]) { worker_read[i].read(QUERY_TEXT.size) }
        if q != QUERY_TEXT
          raise "Fail! Expected #{QUERY_TEXT.inspect} but got #{q.inspect} on request #{req_num.inspect}!"
        end
        reactor.wait_writable(worker_write[i])
        worker_write[i].print(RESPONSE_TEXT)
      end
    end
    workers.push f
  end

  workers.each { |f| f.resume }
  puts "Resumed all worker Fibers, starting reactor..."
  reactor.run
end

### Master code ###

pending_write_msgs = (1..NUM_WORKERS).map { NUM_REQUESTS }
pending_read_msgs = pending_write_msgs.dup

puts "Starting master..."
# Should the master *also* be fiber-based, perhaps with its
# own reactor? Or use a single reactor for master *and*
# worker threads? Interesting question. This is the
# structure I'm starting with. This is clearly very
# comparable to the thread- or process-based tests,
# but probably sacrifices some Fiber performance to do so.
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

puts "Done, waiting for worker background thread..."
worker_thread.join
puts "Done."

if pending_write_msgs.any? { |p| p != 0 } || pending_read_msgs.any? { |p| p != 0}
  puts "Not all messages were delivered!"
  puts "Remaining read: #{pending_read_msgs.inspect}"
  puts "Remaining write: #{pending_write_msgs.inspect}"
else
  puts "All messages delivered successfully..."
end

# Exit
