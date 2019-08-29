#!/usr/bin/env ruby

require 'socket'

RESPONSE_TEXT = "OK".freeze

server = TCPServer.new('localhost', 9090)

loop do
    client = server.accept

    Thread.new do
        client.print RESPONSE_TEXT
        client.close
    end
end
