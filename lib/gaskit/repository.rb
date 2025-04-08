# frozen_string_literal: true

module Gaskit
  class Repository
    COMMON_AR_METHODS = %i[
      find find_by find_by! find_each
      where order limit offset group having
      pluck select exists? create create!
      update update_all destroy destroy_all
      count any? none? all?
    ].freeze

    class << self
      # Prevents instantiation of repository classes.
      #
      # This ensures that subclasses of `Gaskit::Repository` cannot be instantiated
      # directly. If an attempt is made, a `TypeError` will be raised with the class name.
      #
      # @param subclass [Class] the inheriting class
      # @return [void]
      # @raise [TypeError] if the subclass attempts to be instantiated
      def inherited(subclass)
        subclass.define_singleton_method(:new) do
          raise TypeError, "Repositories cannot be instantiated: #{subclass.name}"
        end
        super
      end

      # Defines or retrieves the base model for this repository.
      #
      # When a model is defined, common ActiveRecord-like methods are delegated
      # to the model automatically. The model can only be set once per repository class.
      #
      # @param klass [Class, nil] The model class (e.g., an ActiveRecord model)
      # @return [Class, nil] Returns the currently defined model
      # @raise [StandardError] If a model is set more than once
      #
      # @example Define a model
      #   UserRepository.model(User)
      #
      # @example Retrieve the model
      #   UserRepository.model
      def model(klass = nil)
        return get_model_class! unless klass

        raise "#{name} already has a model set" if instance_variable_defined?(:@model_class)

        instance_variable_set(:@model_class, klass)
        delegate_common_model_methods
      end

      # Returns a logger instance for this repository.
      #
      # The logger is specifically scoped to the repository class, allowing for
      # structured and context-based logging.
      #
      # @return [Gaskit::Logger] The logger instance associated with the class
      #
      # @example Log a message
      #   UserRepository.logger.debug("This is a debug message")
      def logger
        @logger ||= Gaskit::Logger.new(self)
      end

      # Logs the execution time of a block of code.
      #
      # This method measures the duration of the given block. It conditionally logs
      # the timing information based on the log level and configuration settings.
      #
      # If the block raises an exception, the duration is still logged, and the exception
      # is re-raised after logging the error.
      #
      # @param context [Hash] Optional additional context to include in the log
      # @param log_level [Symbol] The log level (default: `:debug`)
      # @yield The block of code to be measured
      # @return [Object] The result of the block execution
      #
      # @raise [StandardError] If the block raises an error
      #
      # @example Log execution time
      #   UserRepository.log_execution_time(log_level: :info) do
      #     perform_work
      #   end
      def log_execution_time(context: {}, log_level: :debug, &block)
        return yield unless should_log_execution_time?(log_level)

        method_name = caller_locations(1, 1)&.first&.label
        duration, result = Gaskit::Helpers.time_execution(&block)

        logger.log(log_level, "#{method_name} completed", context: context.merge(duration: duration))

        result
      rescue StandardError => e
        duration ||= "0.000000"
        logger.error("#{method_name} failed", context: context.merge(duration: duration, error: e.message))

        raise
      end

      private

      # Retrieves the base model for the repository.
      #
      # @return [Class] The model class associated with the repository
      # @raise [StandardError] If no model is defined
      def get_model_class!
        instance_variable_get(:@model_class) || raise("#{name} must declare a model using `model YourModel`")
      end

      # Delegates common ActiveRecord-like methods to the base model.
      #
      # This method iterates through a predefined list of methods (`COMMON_AR_METHODS`)
      # and dynamically defines singleton methods for the repository. These methods
      # call the corresponding methods on the associated model.
      #
      # @return [void]
      #
      # @note This method is called automatically when a model is defined using {#model}.
      def delegate_common_model_methods
        COMMON_AR_METHODS.each do |method_name|
          define_singleton_method(method_name) do |*args, **kwargs, &block|
            model.public_send(method_name, *args, **kwargs, &block)
          end
        end
      end

      # Determines whether execution time logging should occur.
      #
      # This checks various conditions (e.g., debug mode or logger level)
      # to decide if execution timing should be logged.
      #
      # @param log_level [Symbol] The desired log level
      # @return [Boolean] `true` if execution time logging is enabled, otherwise `false`
      def should_log_execution_time?(log_level)
        return true if Gaskit.configuration.debug
        return true if log_level == :debug
        return true if logger.respond_to?(:level) && logger.level <= Logger::DEBUG

        false
      end
    end
  end
end
