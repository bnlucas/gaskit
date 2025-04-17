# frozen_string_literal: true

require "concurrent"

module Gaskit
  module Core
    # Provides before, after, and around hook capabilities to Gaskit operations and queries.
    #
    # Hooks can be registered inline or globally via `Gaskit.hooks`, and may be tagged for selective use.
    #
    # @example Registering inline hooks
    #   class MyOp
    #     include Gaskit::Core::Hookable
    #
    #     before { log_start }
    #     after { log_finish }
    #   end
    module Hookable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # @return [Array<Symbol>] Valid hook types
        VALID_HOOK_TYPES = %i[before after around].freeze

        # Enables hooks for this class, optionally filtering by tag.
        #
        # @param tags [Array<Symbol>] Tags to enable (optional)
        # @param all [Boolean] Whether to run all registered hooks regardless of tag
        # @return [void]
        def use_hooks(*tags, all: tags.empty?)
          registered_hooks.concat(tags.map(&:to_sym)).uniq!
          @run_all_hooks = all
          @enabled = true
        end

        # Registers an inline hook of a given type.
        #
        # @param type [Symbol] One of `:before`, `:after`, or `:around`
        # @param proc [Proc, nil] A proc to register
        # @yield A block hook to register
        # @return [void]
        # @raise [ArgumentError] if the type is invalid or the hook is not callable
        def use_hook(type, proc = nil, &block)
          hook = block_given? ? block : proc
          type, hook = validate_hook!(type, hook)

          inline_hooks[type] << hook
          @enabled = true
        end

        # Shortcut for registering a `before` hook.
        #
        # @see use_hook
        def before(proc = nil, &block)
          use_hook(:before, proc, &block)
        end

        # Shortcut for registering an `around` hook.
        #
        # @see use_hook
        def around(proc = nil, &block)
          use_hook(:around, proc, &block)
        end

        # Shortcut for registering an `after` hook.
        #
        # @see use_hook
        def after(proc = nil, &block)
          use_hook(:after, proc, &block)
        end

        # @return [Boolean] Whether hooks are enabled for this class
        def hooks_enabled?
          @enabled || false
        end

        # @return [Boolean] Whether all global hooks should be run (ignores tags)
        def run_all_hooks?
          @run_all_hooks || false
        end

        # @return [Array<Symbol>] Tags this class uses for global hook filtering
        def registered_hooks
          @registered_hooks ||= []
        end

        # @return [Concurrent::Hash<Symbol, Array<Proc>>] Inline hooks organized by type
        def inline_hooks
          @inline_hooks ||= Concurrent::Hash.new { |h, k| h[k] = [] }
        end

        private

        # Validates a hook type and ensures it's callable.
        #
        # @param type [Symbol] Hook type
        # @param hook [Block, Proc, nil] The callable object
        # @return [Array<(Symbol, Proc)>] Normalized type and validated hook
        # @raise [ArgumentError] if invalid
        def validate_hook!(type, hook)
          type = type.to_sym

          unless VALID_HOOK_TYPES.include?(type)
            raise ArgumentError, "#{type} is not a valid hook type (valid types are #{VALID_HOOK_TYPES.join(", ")})"
          end

          raise ArgumentError, "Hook must be callable" unless hook.respond_to?(:call)

          [type, hook]
        end
      end

      # Applies one or more hook types around a block.
      #
      # @param types [Array<Symbol>] Hook types to apply (`:before`, `:after`, `:around`)
      # @yield The core logic to wrap with hooks
      # @return [Object, nil] The result of the block or final `around` hook
      def apply_hooks(*types, &block)
        return block.call unless self.class.hooks_enabled?

        types = types.map(&:to_sym)
        result = nil

        apply_type_hooks(:before) if types.include?(:before)
        result = apply_type_hooks(:around, &block) if types.include?(:around)
        apply_type_hooks(:after, result: result) if types.include?(:after)

        result
      end

      # Applies all `before` hooks.
      #
      # @return [void]
      def apply_before_hooks
        apply_type_hooks(:before)
      end

      # Applies all `around` hooks, wrapping the given block.
      #
      # @yield The block to wrap
      # @return [Object, nil] The block result
      def apply_around_hooks(&block)
        apply_type_hooks(:around, &block)
      end

      # Applies all `after` hooks, passing in the result of the operation.
      #
      # @param result [Object] The result to pass to `after` hooks
      # @return [void]
      def apply_after_hooks(result)
        apply_type_hooks(:after, result: result)
      end

      private

      # Collects applicable hooks for a given type.
      #
      # @param type [Symbol] The hook type
      # @return [Array<Proc>] The list of hooks to apply
      def collect_hooks(type)
        inline = self.class.inline_hooks[type]
        registered =
          if self.class.run_all_hooks?
            Gaskit.hooks.fetch(type)
          else
            Gaskit.hooks.fetch(type, self.class.registered_hooks)
          end

        (registered + inline).uniq
      end

      # Applies all hooks of a given type.
      #
      # @param type [Symbol] The hook type
      # @param result [Object, nil] The result to pass to `after` hooks
      # @yield For `around` hooks, the wrapped block
      # @return [Object, nil] The result (for `around` or `after`)
      def apply_type_hooks(type, result: nil, &block)
        return result unless self.class.hooks_enabled?

        hooks = collect_hooks(type)
        process_hooks(type, hooks, result, &block)
      end

      # Executes hooks based on type.
      #
      # @param type [Symbol] The hook type
      # @param hooks [Array<Proc>] The list of hooks
      # @param result [Object, nil] The result to pass to `after` hooks
      # @yield The block to wrap for `around` hooks
      # @return [Object, nil] The result after hook processing
      def process_hooks(type, hooks, result, &block)
        case type
        when :before
          hooks.each { |hook| instance_exec(&hook) }
        when :around
          result = hooks.reverse.inject(block) do |acc, hook|
            proc { instance_exec(acc, &hook) }
          end.call
        when :after
          hooks.each { |hook| instance_exec(result, &hook) }
        end

        result
      end
    end
  end
end
