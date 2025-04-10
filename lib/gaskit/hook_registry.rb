# frozen_string_literal: true

module Gaskit
  # Gaskit::HookRegistry manages registration and retrieval of global hooks for
  # operation-style lifecycles (e.g., `before`, `after`, `around`).
  #
  # Hooks are grouped by type and tag. They are used in classes that include `Gaskit::Hookable`.
  class HookRegistry
    def initialize
      @hooks = {
        before: Hash.new { |h, k| h[k] = [] },
        after: Hash.new { |h, k| h[k] = [] },
        around: Hash.new { |h, k| h[k] = [] }
      }
    end

    # Registers a new hook under a given type and tag.
    #
    # @param type [Symbol] The lifecycle type: `:before`, `:after`, or `:around`
    # @param tag [Symbol, String] A symbolic tag to group related hooks (e.g., :audit, :metrics)
    # @param callable [#call, nil] A callable object (optional if block is given)
    # @yield [hook] A block to be registered as a hook if no callable is passed
    # @return [void]
    # @raise [ArgumentError] If the hook is not callable or the type is invalid
    def register(type, tag, callable = nil, &block)
      hook = callable || block
      raise ArgumentError, "Hook must respond to #call" unless hook.respond_to?(:call)
      raise ArgumentError, "Unknown hook type: #{type}" unless @hooks.key?(type)

      @hooks[type][tag.to_sym] << hook
    end

    # Checks if a hook tag is registered under a specific type.
    #
    # @param type [Symbol] The hook type (`:before`, `:after`, or `:around`)
    # @param tag [Symbol, String] The tag to check
    # @return [Boolean] Whether a hook with that tag exists for the given type
    def registered?(type, tag)
      @hooks[type].key?(tag.to_sym)
    end

    # Fetches hooks for the given type, filtered by tags.
    #
    # @param type [Symbol] The hook type (`:before`, `:after`, or `:around`)
    # @param tags [Array<Symbol, String>, nil] One or more tags to filter hooks by. If nil or empty,
    #   returns all hooks of that type.
    # @return [Array<#call>] An array of callable hooks
    def fetch(type, tags = nil)
      return @hooks[type].values.flatten if tags.nil? || tags.empty?

      (tags || []).flat_map { |tag| @hooks[type][tag.to_sym] }
    end

    # Returns all registered tags for a given hook type.
    #
    # @param type [Symbol] The hook type (`:before`, `:after`, or `:around`)
    # @return [Array<Symbol>] List of registered tags under that type
    def registered_tags(type)
      @hooks[type].keys
    end
  end
end
