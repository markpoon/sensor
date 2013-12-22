require 'bundler/setup'
Bundler.require :default
require './app'
run Rack::Cascade.new [API, Web]
