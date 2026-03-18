# frozen_string_literal: true

require_relative "gaskit/castkit"
require_relative "gaskit/version"
require_relative "gaskit/error"
require_relative "gaskit/operation_result"
require_relative "gaskit/logger"
require_relative "gaskit/operation"
require_relative "gaskit/repository"
require_relative "gaskit/flow"
require_relative "gaskit/core"

require_relative "gaskit/boot/service"
require_relative "gaskit/boot/query"

# Gaskit is a lightweight, extensible framework for building structured application operations.
#
# It provides a clear architecture for defining, executing, and managing operations,
# supporting common patterns like services and queries, early exits, context-aware logging,
# and standardized result wrapping.
#
# @example Configuring Gaskit
#   Gaskit.config do |c|
#     c.setup_logger(Logger.new(STDOUT), level: ::Logger::INFO, formatter: Gaskit::Logger.formatter(:json))
#     c.context_provider = -> { { request_id: SecureRandom.uuid } }
#   end
#
# @example Defining a service
#   class MyService < Gaskit::Service
#     def call
#       # do work
#       "done"
#     end
#   end
#
# @see Gaskit::Operation
# @see Gaskit::Service
# @see Gaskit::Query
# @see Gaskit::Configuration
module Gaskit; end
