#!/bin/bash -l

rvm use 2.0.0-p0

./fiber_server.rb &
wrk http://localhost:9292/
