# frozen_string_literal: true

module Gaskit
  module Stores
    # Abstract base class for implementing Gaskit-compatible stores.
    # Provides a namespaced key structure and optional error-handled access patterns.
    #
    # Subclasses should implement all bang methods (e.g., `read!`, `write!`, etc.).
    # Non-bang methods provide safe wrappers that log and suppress errors.
    #
    # @example Implementing a custom store
    #   class InMemoryStore < Gaskit::Stores::BaseStore
    #     def read!(*keys, **options)
    #       ...
    #     end
    #   end
    class Base
      # @return [String] The cache key namespace.
      attr_reader :namespace

      # @return [Gaskit::Logger] The logger instance used by this store.
      attr_reader :logger

      # Initializes a new store instance.
      #
      # @param namespace [String] Prefix used to namespace all keys.
      # @param key_separator [String] Separator between namespace and key, defaults to ":".
      # @param logger [Gaskit::Logger, nil] Optional logger, defaults to Gaskit::Logger.new.
      def initialize(namespace, key_separator: ":", logger: nil)
        logger ||= Gaskit::Logger.new(self.class)

        @namespace = namespace.freeze
        @key_separator = key_separator.freeze
        @logger = logger
      end

      # Builds a fully-qualified namespaced key.
      #
      # @param key [String] Key suffix.
      # @return [String] Fully qualified key.
      def namespace_key(key)
        "#{@namespace}#{@key_separator}#{key}"
      end

      # Builds a namespaced wildcard pattern for scanning keys.
      #
      # @param pattern [String] Suffix pattern, defaults to '*'.
      # @return [String] Fully qualified pattern.
      def namespace_pattern(pattern = "*")
        namespace_key(pattern)
      end

      # Checks if a key exists (safe).
      #
      # Wraps {#key_exists!} in a `safe_op` block, returning false on failure.
      #
      # @param key [String] The key to check.
      # @return [Boolean] True if the key exists, false if not or on failure.
      def key_exists?(key)
        safe_op { key_exists!(key) } || false
      end

      # Checks if a key exists (strict).
      #
      # @param key [String] The key to check.
      # @return [Boolean] True if the key exists.
      # @raise [NotImplementedError] Must be implemented by the subclass.
      def key_exists!(key)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Safely fetches a value from the store or computes and writes it if missing.
      #
      # @param key [String] The key to fetch.
      # @param force [Boolean] If true, bypasses the cache and recomputes the value.
      # @param options [Hash] Optional options passed to `read` and `write`.
      # @yield Executes if value is missing or `force` is true.
      # @yieldreturn [Object] The value to write and return.
      # @return [Object, nil] The cached or computed value, or nil on failure.
      def fetch(key, force: false, **options)
        safe_op { fetch!(key, force: force, **options) }
      end

      # Strictly fetches a value from the store or computes and writes it if missing.
      #
      # @param key [String] The key to fetch.
      # @param force [Boolean] If true, bypasses the cache and recomputes the value.
      # @param options [Hash] Optional options passed to `read!` and `write!`.
      # @yield Executes if value is missing or `force` is true.
      # @yieldreturn [Object] The value to write and return.
      # @return [Object] The cached or computed value.
      # @raise [StandardError] Any error raised during read, write, or block execution.
      def fetch!(key, force: false, **options)
        unless force
          cached = read(key, **options)
          return cached if cached
        end

        result = yield
        write(key, result, **options) unless result.nil?
        result
      end

      # Reads one or more keys (safe).
      #
      # @param keys [Array<String>] Keys to read.
      # @param options [Hash] Optional read options.
      # @return [Object, nil] The result or nil on failure.
      def read(*keys, **options)
        safe_op { read!(*keys, **options) }
      end

      # Reads one or more keys (strict).
      #
      # @param keys [Array<String>] Keys to read.
      # @param options [Hash] Optional read options.
      # @return [Object] The result.
      # @raise [NotImplementedError] Must be implemented by the subclass.
      def read!(*keys, **options)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Writes a key (safe).
      #
      # @param key [String] The key to write.
      # @param value [Object] The value to write.
      # @param options [Hash] Optional write options.
      # @return [Boolean] True on success, false on failure.
      def write(key, value, **options)
        safe_op { write!(key, value, **options) } || false
      end

      # Writes a key (strict).
      #
      # @param key [String] The key to write.
      # @param value [Object] The value to write.
      # @param options [Hash] Optional write options.
      # @return [Boolean] True on success.
      # @raise [NotImplementedError] Must be implemented by the subclass.
      def write!(key, value, **options)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Deletes one or more keys (safe).
      #
      # @param keys [Array<String>] Keys to delete.
      # @param options [Hash] Optional delete options.
      # @return [Integer, nil] Number of keys deleted or nil on failure.
      def delete(*keys, **options)
        safe_op { delete!(*keys, **options) }
      end

      # Deletes one or more keys (strict).
      #
      # @param keys [Array<String>] Keys to delete.
      # @param options [Hash] Optional delete options.
      # @return [Integer] Number of keys deleted.
      # @raise [NotImplementedError] Must be implemented by the subclass.
      def delete!(*keys, **options)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Safe read of one or more keys. Errors are caught and logged.
      #
      # @param keys [Array<String>]
      # @param purge_on_error [Boolean] Whether to purge corrupted keys
      # @return [Object, Hash{String => Object, nil}, nil]
      def read_all(*keys, **options)
        safe_op { read_all!(*keys, **options) }
      end

      def read_all!(*keys, **options)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Writes multiple keys at once (safe).
      #
      # @param data [Hash<String, Object>] A hash of key-value pairs.
      # @param options [Hash] Optional write options.
      # @return [Boolean, nil] True on success, false on failure.
      def write_all(data, **options)
        safe_op { write_all!(data, **options) }
      end

      # Writes multiple keys at once (strict).
      #
      # @param data [Hash<String, Object>] A hash of key-value pairs.
      # @param options [Hash] Optional write options.
      # @return [Boolean] True on success.
      # @raise [NotImplementedError] Must be implemented by the subclass.
      def write_all!(data, **options)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Flushes all keys in the namespace (safe).
      #
      # @param options [Hash] Optional flush options.
      # @return [Boolean] True on success, false on failure.
      def flush_namespace(**options)
        safe_op { flush_namespace!(**options) } || false
      end

      # Flushes all keys in the namespace (strict).
      #
      # @param options [Hash] Optional flush options.
      # @return [Boolean] True on success.
      # @raise [NotImplementedError] Must be implemented by the subclass.
      def flush_namespace!(**options)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      protected

      # Wraps a block in error handling and logs any StandardError.
      #
      # @yield Executes a potentially unsafe operation.
      # @return [Object, Hash{String => Object, nil}, nil] The result of the block, or nil on error.
      def safe_op
        yield
      rescue StandardError => e
        logger.error("[#{self.class}] #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
