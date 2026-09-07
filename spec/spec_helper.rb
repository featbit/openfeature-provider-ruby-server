# frozen_string_literal: true

require "featbit/openfeature"
require "logger"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.after { OpenFeature::SDK.shutdown }
end

def flag(key, type, value, **overrides)
  {
    "id" => key, "key" => key, "name" => key, "variationType" => type,
    "isEnabled" => true, "isArchived" => false,
    "variations" => [{ "id" => "on", "value" => value }, { "id" => "off", "value" => value }],
    "disabledVariationId" => "off", "targetUsers" => [], "rules" => [],
    "fallthrough" => { "variations" => [{ "id" => "on", "rollout" => [0, 1] }] },
    "updatedAt" => "2026-01-01T00:00:00Z"
  }.merge(overrides.transform_keys(&:to_s))
end

def offline_options(*flags)
  FeatBit::Options.new(offline: true, logger: Logger.new(File::NULL), bootstrap: {
    "messageType" => "data-sync",
    "data" => { "eventType" => "full", "featureFlags" => flags, "segments" => [] }
  })
end
