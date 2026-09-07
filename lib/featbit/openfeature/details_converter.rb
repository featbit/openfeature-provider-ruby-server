# frozen_string_literal: true

module FeatBit
  module OpenFeature
    class DetailsConverter
      API = ::OpenFeature::SDK::Provider
      ERROR_CODES = {
        client_not_ready: API::ErrorCode::PROVIDER_NOT_READY,
        flag_not_found: API::ErrorCode::FLAG_NOT_FOUND,
        user_not_specified: API::ErrorCode::TARGETING_KEY_MISSING,
        wrong_type: API::ErrorCode::TYPE_MISMATCH
      }.freeze
      REASONS = {
        "flag off" => API::Reason::DISABLED,
        "target match" => API::Reason::TARGETING_MATCH,
        "rule match" => API::Reason::TARGETING_MATCH,
        "fall through all rules" => API::Reason::DEFAULT
      }.freeze
      TYPES = {
        boolean: [TrueClass, FalseClass], string: [String], number: [Numeric],
        integer: [Numeric], float: [Numeric], object: [Hash, Array]
      }.freeze

      def self.error(default_value, code, message)
        API::ResolutionDetails.new(value: default_value, reason: API::Reason::ERROR,
                                   error_code: code, error_message: message)
      end

      def self.convert(detail, type, default_value)
        unless detail.success?
          return error(default_value, ERROR_CODES.fetch(detail.error_kind, API::ErrorCode::GENERAL),
                       detail.error_message || detail.reason)
        end

        value = detail.value
        unless TYPES.fetch(type).any? { |klass| value.is_a?(klass) }
          return error(default_value, API::ErrorCode::TYPE_MISMATCH, "Flag value is not of type #{type}")
        end

        value = value.to_i if type == :integer
        value = value.to_f if type == :float
        metadata = { "featbit.reason" => detail.reason, "featbit.in_experiment" => detail.send_to_experiment == true }
        metadata["featbit.flag_name"] = detail.flag_name unless detail.flag_name.nil?
        API::ResolutionDetails.new(value: value, reason: REASONS.fetch(detail.reason, API::Reason::UNKNOWN),
                                   variant: detail.variation_id&.to_s, flag_metadata: metadata)
      end
    end
  end
end
