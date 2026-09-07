# frozen_string_literal: true

module FeatBit
  module OpenFeature
    # Owns the supplied or newly created client and closes it on shutdown.
    class Provider
      include ::OpenFeature::SDK::Provider::EventEmitter

      attr_reader :client, :metadata

      def initialize(options = nil, client: nil)
        raise ArgumentError, "Provide options or client, not both" if options && client
        unless client || options.is_a?(FeatBit::Options)
          raise ArgumentError, "FeatBit::Options or a FeatBit client is required"
        end

        @client = client || FeatBit::Client.new(options)
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: "FeatBit").freeze
        @status_listener = @client.status_provider.add_listener { |status, message| status_changed(status, message) }
        @flag_listener = @client.add_flag_change_listener do |key|
          emit_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, flags_changed: [key])
        end
      end

      def init(_evaluation_context = nil)
        return if client.initialized? && [FeatBit::Status::READY, FeatBit::Status::INTERRUPTED,
                                         FeatBit::Status::OFFLINE].include?(client.status_provider.status)

        raise ContextConverter::InvalidContext.new(
          ::OpenFeature::SDK::Provider::ErrorCode::PROVIDER_NOT_READY, "FeatBit client is not ready"
        )
      end

      def shutdown
        client.status_provider.remove_listener(@status_listener)
        client.remove_flag_change_listener(@flag_listener)
        detach
        client.close
      end

      %i[boolean string number integer float object].each do |type|
        define_method("fetch_#{type}_value") do |flag_key:, default_value:, evaluation_context: nil|
          resolve(type, flag_key, default_value, evaluation_context)
        end
      end

      def track(tracking_event_name, evaluation_context: nil, tracking_event_details: nil)
        user = ContextConverter.convert(evaluation_context)
        client.track(user, tracking_event_name, tracking_event_details&.value || 1.0)
      rescue ContextConverter::InvalidContext
        false
      end

      private

      def resolve(type, key, default_value, context)
        user = ContextConverter.convert(context)
        DetailsConverter.convert(client.variation_detail(key, user, default_value), type, default_value)
      rescue ContextConverter::InvalidContext => e
        DetailsConverter.error(default_value, e.error_code, e.message)
      rescue StandardError
        DetailsConverter.error(default_value, ::OpenFeature::SDK::Provider::ErrorCode::GENERAL,
                               "FeatBit evaluation failed")
      end

      def status_changed(status, message)
        events = ::OpenFeature::SDK::ProviderEvent
        case status
        when FeatBit::Status::READY
          emit_event(events::PROVIDER_READY)
        when FeatBit::Status::INTERRUPTED
          emit_event(events::PROVIDER_STALE, message: message)
        when FeatBit::Status::STARTING, FeatBit::Status::OFFLINE, FeatBit::Status::FAILED, FeatBit::Status::CLOSED
          emit_event(events::PROVIDER_ERROR, error_code: ::OpenFeature::SDK::Provider::ErrorCode::PROVIDER_NOT_READY,
                                            message: message || "FeatBit client is not ready")
        end
      end
    end
  end
end
