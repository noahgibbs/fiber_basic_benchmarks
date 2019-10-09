#!/usr/bin/env ruby

require 'socket'
require 'fiber'
require 'json'

# TODO: make these much larger, see if we're effectively batching
# even if we don't mean to...
QUERY_TEXT = "STATUS".freeze
RESPONSE_TEXT = "OK".freeze

if ARGV.size != 3
  STDERR.puts "Usage: ./fiber_test <num workers> <number of requests/batch> <output filename>"
  exit 1
end

NUM_WORKERS = ARGV[0].to_i
NUM_REQUESTS = ARGV[1].to_i
OUTFILE = ARGV[2]

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
        raise "Nil io passed to wait_readable!" if io.nil?
        @readable[io] = Fiber.current
        Fiber.yield
        @readable.delete(io)

        return yield if block_given?
    end

    def wait_writable(io)
        raise "Nil io passed to wait_writable!" if io.nil?
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

#puts "Setting up pipes..."
working_t0 = Time.now

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

reactor = Reactor.new

#puts "Setting up fibers..."
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
#puts "Resumed all worker Fibers..."

### Master code ###

#puts "Starting master..."

master_fiber = Fiber.new do
  master_subfibers = []
  NUM_WORKERS.times do |worker_num|
    # This fiber will handle a single batch
    f = Fiber.new do
      NUM_REQUESTS.times do |req_num|
        reactor.wait_writable(master_write[worker_num]) do
          master_write[worker_num].print QUERY_TEXT
        end
        buf = reactor.wait_readable(master_read[worker_num]) do
          master_read[worker_num].read(RESPONSE_TEXT.size)
        end
        if buf != RESPONSE_TEXT
          raise "Error! Fiber no. #{worker_num} on req #{req_num} expected #{RESPONSE_TEXT.inspect} but got #{buf.inspect}!"
        end
      end
    end
    master_subfibers.push f
    f.resume
  end
end
master_fiber.resume

#puts "Starting reactor..."
reactor.run
working_time = Time.now - working_t0
#puts "Done, finished all reactor Fibers!"

out_data = {
  workers: NUM_WORKERS,
  requests_per_batch: NUM_REQUESTS,
  time: working_time,
  success: true,
}

File.open(OUTFILE, "w") { |f| f.write JSON.pretty_generate(out_data) }

exit 0
