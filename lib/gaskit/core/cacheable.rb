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
        # @param namespace [String] Required namespace to scope cache keys
        # @param options [Hash] Additional options passed to the store constructor
        # @return [Hash] Cache store configuration
        def cache_store(name = nil, namespace:, **options)
          @cache_store ||= { name: name, namespace: namespace, options: options }
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
        return if self.class.cache_store.nil?

        name, namespace, options = self.class.cache_store.values_at(:name, :namespace, :options)
        klass = Gaskit.configuration.fetch_cache_store(name) if name
        klass ||= Gaskit.configuration.cache_store

        @cache = klass.new(namespace, logger: logger, **options)
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
        @prefetch_cache = cache.read_all!(*keys)
      end

      # Retrieves a prefetched cache value, with optional fallback behavior.
      #
      # @param key [String] The namespaced cache key
      # @param default [Object, nil] Optional default value if key not found
      # @yield [] Optional block to return value if key not found
      # @return [Object, nil] The cached value, block result, or default
      def prefetched(key, default = nil, &block)
        return prefetch_cache[key] if prefetch_cache.key?(key)
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
        return unless !cache_enabled? && Gaskit.configuration.enforce_cache_store

        raise Gaskit::Error, "No cache store configured"
      end
    end
  end
end
