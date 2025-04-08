# frozen_string_literal: true

require "rails/generators/base"

module Gaskit
  module Generators
    # Generates a repository for a given model name
    #
    # @example
    #   rails generate gaskit:repository User
    #
    #   # Creates:
    #   # app/repositories/user_repository.rb
    #
    #   # With contents:
    #   # class UserRepository < Gaskit::Repository
    #   #   model User
    #   # end
    class RepositoryGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      def create_repository_file
        @model_name = class_name
        @repository_class_name = "#{class_name}Repository"
        @file_path = File.join("app/repositories", class_path, "#{file_name}_repository.rb")

        template "repository.rb.tt", @file_path
      end

      private

      def file_name
        super.underscore
      end
    end
  end
end
