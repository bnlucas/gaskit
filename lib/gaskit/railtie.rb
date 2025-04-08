# frozen_string_literal: true

require "rails/railtie"

module Gaskit
  class Railtie < Rails::Railtie
    config.app_generators do |g|
      g.templates.unshift File.expand_path("../../generators", __dir__)
    end
  end
end
