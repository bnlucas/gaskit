# frozen_string_literal: true

require "concurrent"

module Gaskit
  module Hookable
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      VALID_HOOK_TYPES = %i[before after around].freeze

      def use_hooks(*tags, all: tags.empty?)
        registered_hooks.concat(tags.map(&:to_sym)).uniq!

        @run_all_hooks = all
        @enabled = true
      end

      def use_hook(type, proc = nil, &block)
        hook = block_given? ? block : proc
        type, hook = validate_hook!(type, hook)

        inline_hooks[type] << hook
        @enabled = true
      end

      def before(proc = nil, &block)
        use_hook(:before, proc, &block)
      end

      def around(proc = nil, &block)
        use_hook(:around, proc, &block)
      end

      def after(proc = nil, &block)
        use_hook(:after, proc, &block)
      end

      def hooks_enabled?
        @enabled || false
      end

      def run_all_hooks?
        @run_all_hooks || false
      end

      def registered_hooks
        @registered_hooks ||= []
      end

      def inline_hooks
        @inline_hooks ||= Concurrent::Hash.new { |h, k| h[k] = [] }
      end

      private

      def validate_hook!(type, hook)
        type = type.to_sym

        unless VALID_HOOK_TYPES.include?(type)
          raise ArgumentError, "#{type} is not a valid hook type (valid types are #{VALID_HOOK_TYPES.join(", ")})"
        end

        raise ArgumentError, "Hook must be callable" unless hook.respond_to?(:call)

        [type, hook]
      end
    end

    def apply_hooks(*types, &block)
      return block.call unless self.class.hooks_enabled?

      types = types.map(&:to_sym)
      result = nil

      apply_type_hooks(:before) if types.include?(:before)
      result = apply_type_hooks(:around, &block) if types.include?(:around)
      apply_type_hooks(:after, result: result) if types.include?(:after)

      result
    end

    def apply_before_hooks
      apply_type_hooks(:before)
    end

    def apply_around_hooks(&block)
      apply_type_hooks(:around, &block)
    end

    def apply_after_hooks(result)
      apply_type_hooks(:after, result: result)
    end

    private

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

    def apply_type_hooks(type, result: nil, &block)
      return result unless self.class.hooks_enabled?

      hooks = collect_hooks(type)
      process_hooks(type, hooks, result, &block)
    end

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
