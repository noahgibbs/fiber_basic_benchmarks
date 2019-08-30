#!/usr/bin/env ruby

require 'socket'

RESPONSE_TEXT = "OK".freeze

server = TCPServer.new('localhost', 9090)

loop do
    client = server.accept

    Thread.new do
        query = client.read(6)   # Or sysread?
        if query == "STATUS"
          client.print RESPONSE_TEXT
        else
          STDERR.puts "READ gave bad result: #{query.inspect}, not STATUS"
        end
        client.close
    end
end
