# frozen_string_literal: true

module FeatBit
  module OpenFeature
    class ContextConverter
      class InvalidContext < StandardError
        attr_reader :error_code

        def initialize(error_code, message)
          @error_code = error_code
          super(message)
        end
      end

      def self.convert(context)
        codes = ::OpenFeature::SDK::Provider::ErrorCode
        unless context.nil? || context.is_a?(::OpenFeature::SDK::EvaluationContext)
          raise InvalidContext.new(codes::INVALID_CONTEXT, "Expected an OpenFeature evaluation context")
        end

        key = context&.targeting_key
        if key.nil? || key == ""
          raise InvalidContext.new(codes::TARGETING_KEY_MISSING, "A non-empty targeting_key is required")
        end
        unless key.is_a?(String)
          raise InvalidContext.new(codes::INVALID_CONTEXT, "targeting_key must be a string")
        end

        name = context.field("name")
        unless name.nil? || name.is_a?(String)
          raise InvalidContext.new(codes::INVALID_CONTEXT, "name must be a string")
        end

        custom = context.fields.reject { |field, _| %w[targeting_key name].include?(field) }
        FeatBit::User.new(key, name: name, custom: custom)
      end
    end
  end
end
