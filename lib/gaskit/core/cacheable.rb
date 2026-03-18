# frozen_string_literal: true

module Gaskit
  module Core
    # Provides caching support to operations and queries using a class-configured store.
    #
    # Includes optional prefetching and fallback-aware value retrieval.
    module Cacheable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Defines the cache store configuration for the operation or query.
        #
        # This does not instantiate the store; it stores configuration used later by instances.
        #
        # @param name [Symbol, nil] Optional registered store name
        # @param namespace [String, nil] Optional namespace to scope cache keys (defaults to name or class name)
        # @note Pass `:disabled` as the name to disable caching for the class.
        # @param options [Hash] Additional options passed to the store constructor
        # @return [Hash] Cache store configuration
        def cache_store(name = nil, namespace: nil, **options)
          return @cache_store if defined?(@cache_store) && name.nil? && namespace.nil?
          return @cache_store = :disabled if name == :disabled

          namespace ||= name || self.name
          @cache_store = { name: name, namespace: namespace, options: options }
        end

        # Directly assigns a cache store config hash (used for testing/mocking).
        #
        # @param store [Hash] A preconfigured cache store hash
        # @return [void]
        def override_cache_store(store)
          @cache_store = store
        end

        # Clears the stored cache store config (used for resetting between runs).
        #
        # @return [void]
        def reset_cache_store!
          @cache_store = nil
        end
      end

      # Returns the instantiated cache store for this instance.
      #
      # @return [Object, nil] The configured cache store or nil if not configured
      def cache
        return @cache if @cache

        config = resolved_cache_config
        return unless config

        store_class, global_options = resolve_store_config
        options = merge_cache_options(config[:options], global_options)
        cache_class = resolve_cache_class(config[:name], store_class)

        @cache = cache_class.new(config[:namespace], logger: logger, **options)
      end

      # @return [Boolean] true if a cache store is configured and instantiated
      def cache_enabled?
        !cache.nil?
      end

      # Internal memoized cache for prefetched keys.
      #
      # @return [Hash<String, Object>] The prefetched cache entries
      def prefetch_cache
        @prefetch_cache ||= {}
      end

      # Safely attempts to prefetch one or more keys from the cache.
      # Logs a warning on failure instead of raising.
      #
      # @param keys [Array<String>] One or more cache keys to read.
      # @return [void]
      def cache_prefetch(*keys)
        cache_prefetch!(*keys)
      rescue StandardError => e
        logger.warn("Cache prefetch failed: #{e.message}")
      end

      # Prefetches one or more keys from the cache.
      # Replaces the current `prefetch_cache` contents.
      #
      # @param keys [Array<String>] One or more cache keys to read.
      # @raise [RuntimeError] if caching is enforced but no store is configured
      # @return [void]
      def cache_prefetch!(*keys)
        validate_cache!
        return unless cache_enabled?

        @prefetch_cache = cache.read_all!(*keys)
      end

      # Retrieves a prefetched cache value, with optional fallback behavior.
      #
      # @param key [String] The namespaced cache key
      # @param default [Object, nil] Optional default value if key not found
      # @yield [] Optional block to return value if key not found
      # @return [Object, nil] The cached value, block result, or default
      def prefetched(key, default = nil, &block)
        if prefetch_cache.key?(key)
          value = prefetch_cache[key]
          return value unless value.nil?
        end

        return block.call if block_given?

        default
      end

      # Clears all previously prefetched cache values.
      #
      # @return [void]
      def clear_prefetched_cache!
        @prefetch_cache = {}
      end

      private

      # Validates that a cache store is configured and raises if it's required.
      #
      # @raise [RuntimeError] if no cache store is configured and enforcement is enabled
      # @return [void]
      def validate_cache!
        return if cache_enabled?
        return unless Gaskit.configuration.enforce_cache_store

        raise Gaskit::Error, "No cache store configured"
      end

      # Returns the class-level cache config unless disabled.
      #
      # @return [Hash, nil]
      def resolved_cache_config
        config = self.class.cache_store
        return if config.nil? || config == :disabled

        config
      end

      # Resolves the global cache store config into a class and options hash.
      #
      # @return [Array<(Class, Hash)>]
      def resolve_store_config
        store_config = Gaskit.configuration.cache_store
        if store_config.is_a?(Hash) && store_config.key?(:store)
          [store_config[:store], store_config[:options] || {}]
        else
          [store_config, {}]
        end
      end

      # Resolves the cache store class based on name or global default.
      #
      # @return [Class]
      def resolve_cache_class(name, default_class)
        return Gaskit.configuration.fetch_cache_store(name) if name

        default_class
      end

      # Merges per-class and global cache options.
      #
      # @return [Hash]
      def merge_cache_options(config_options, global_options)
        (global_options || {}).merge(config_options || {})
      end
    end
  end
end
