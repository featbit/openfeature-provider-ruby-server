# frozen_string_literal: true

require "spec_helper"

RSpec.describe FeatBit::OpenFeature::Provider do
  let(:context) { OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-1", name: "Alice", country: "FR") }
  let(:provider) do
    described_class.new(offline_options(
      flag("bool", "boolean", "true"), flag("string", "string", "hello"),
      flag("number", "number", "12.75"), flag("object", "json", '{"enabled":true}'),
      flag("array", "json", '[1,"two"]'), flag("disabled", "boolean", "false", isEnabled: false),
      flag("target", "string", "targeted", targetUsers: [{ "keyIds" => ["user-1"], "variationId" => "on" }]),
      flag("rule", "string", "matched", rules: [{ "conditions" => [{ "property" => "country", "op" => "Equal", "value" => "FR" }],
                                                  "variations" => [{ "id" => "on", "rollout" => [0, 1] }] }])
    ))
  end
  let(:client) do
    OpenFeature::SDK.configure { |config| config.set_provider_and_wait(provider) }
    OpenFeature::SDK.build_client(evaluation_context: context)
  end

  after { provider.shutdown }

  { boolean: ["bool", false, true], string: ["string", "fallback", "hello"],
    number: ["number", 0, 12.75], integer: ["number", 0, 12], float: ["number", 0.0, 12.75],
    object: ["object", {}, { "enabled" => true }] }.each do |type, (key, fallback, expected)|
    it "evaluates #{type} through the real OpenFeature and FeatBit SDKs" do
      detail = client.public_send("fetch_#{type}_details", flag_key: key, default_value: fallback)
      expect(detail.value).to eq(expected)
      expect(detail.error_code).to be_nil
      expect(detail.variant).to eq("on")
      expect(detail.reason).to eq("DEFAULT")
    end

    it "rejects a mismatched #{type} result" do
      wrong_key = type == :string ? "bool" : "string"
      detail = client.public_send("fetch_#{type}_details", flag_key: wrong_key, default_value: fallback)
      expect(detail.value).to eq(fallback)
      expect(detail.error_code).to eq("TYPE_MISMATCH")
      expect(detail.reason).to eq("ERROR")
      expect(detail.variant).to be_nil
    end
  end

  it "supports JSON arrays" do
    expect(client.fetch_object_value(flag_key: "array", default_value: [])).to eq([1, "two"])
  end

  { "disabled" => "DISABLED", "target" => "TARGETING_MATCH", "rule" => "TARGETING_MATCH" }.each do |key, reason|
    it "maps the #{key} reason" do
      detail = provider.fetch_string_value(flag_key: key == "disabled" ? "string" : key,
                                           default_value: "", evaluation_context: context)
      detail = provider.fetch_boolean_value(flag_key: key, default_value: true, evaluation_context: context) if key == "disabled"
      expect(detail.reason).to eq(reason)
    end
  end

  it "preserves flag metadata" do
    detail = client.fetch_string_details(flag_key: "string", default_value: "")
    expect(detail.flag_metadata).to include("featbit.reason" => "fall through all rules", "featbit.flag_name" => "string")
  end

  it "returns the caller default for missing flags" do
    detail = client.fetch_boolean_details(flag_key: "missing", default_value: false)
    expect(detail.value).to be(false)
    expect(detail.error_code).to eq("FLAG_NOT_FOUND")
  end

  [nil, OpenFeature::SDK::EvaluationContext.new, OpenFeature::SDK::EvaluationContext.new(targeting_key: "")].each do |invalid|
    it "requires a non-empty targeting key (#{invalid.inspect})" do
      result = provider.fetch_boolean_value(flag_key: "bool", default_value: false, evaluation_context: invalid)
      expect(result.error_code).to eq("TARGETING_KEY_MISSING")
    end
  end

  [42, OpenFeature::SDK::EvaluationContext.new(targeting_key: 42),
   OpenFeature::SDK::EvaluationContext.new(targeting_key: "u", name: false)].each do |invalid|
    it "rejects invalid contexts (#{invalid.inspect})" do
      result = provider.fetch_boolean_value(flag_key: "bool", default_value: false, evaluation_context: invalid)
      expect(result.error_code).to eq("INVALID_CONTEXT")
    end
  end

  it "maps context fields without mutating the context" do
    user = FeatBit::OpenFeature::ContextConverter.convert(context)
    expect(user.key).to eq("user-1")
    expect(user.name).to eq("Alice")
    expect(user.custom).to eq("country" => "FR")
    expect(context.fields).to include("targeting_key" => "user-1", "name" => "Alice")
  end

  it "merges invocation context through OpenFeature" do
    override = OpenFeature::SDK::EvaluationContext.new(targeting_key: "someone-else")
    expect(client.fetch_string_details(flag_key: "target", default_value: "", evaluation_context: override).reason).to eq("DEFAULT")
  end

  it "reports uninitialized clients" do
    empty = described_class.new(FeatBit::Options.new(offline: true))
    expect { empty.init }.to raise_error(FeatBit::OpenFeature::ContextConverter::InvalidContext)
    expect(empty.fetch_boolean_value(flag_key: "bool", default_value: false, evaluation_context: context).error_code).to eq("PROVIDER_NOT_READY")
  ensure
    empty&.shutdown
  end

  it "closes an injected client and cannot be initialized again" do
    sdk_client = FeatBit::Client.new(offline_options)
    wrapper = described_class.new(client: sdk_client)
    expect(wrapper.client).to equal(sdk_client)
    expect(wrapper.shutdown).to be(true)
    expect(wrapper.shutdown).to be(true)
    expect { wrapper.init }.to raise_error(FeatBit::OpenFeature::ContextConverter::InvalidContext)
  end

  it "rejects ambiguous construction" do
    expect { described_class.new }.to raise_error(ArgumentError)
    expect { described_class.new(offline_options, client: provider.client) }.to raise_error(ArgumentError)
  end

  it "contains unexpected evaluation errors" do
    allow(provider.client).to receive(:variation_detail).and_raise("internal failure")
    detail = provider.fetch_boolean_value(flag_key: "bool", default_value: false, evaluation_context: context)
    expect(detail.error_code).to eq("GENERAL")
    expect(detail.value).to be(false)
  end

  it "forwards tracking values including zero" do
    expect(provider.client).to receive(:track).with(have_attributes(key: "user-1"), "purchase", 0)
    client.track("purchase", tracking_event_details: OpenFeature::SDK::TrackingEventDetails.new(value: 0))
  end

  it "defaults tracking value to one and rejects missing context" do
    expect(provider.client).to receive(:track).with(have_attributes(key: "user-1"), "purchase", 1.0)
    provider.track("purchase", evaluation_context: context)
    expect(provider.track("purchase")).to be(false)
  end

  it "forwards stale, recovery and configuration events and removes listeners on shutdown" do
    events = []
    client.add_handler(OpenFeature::SDK::ProviderEvent::PROVIDER_STALE) { |details| events << details }
    client.add_handler(OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED) { |details| events << details }
    provider.client.status_provider.update(FeatBit::Status::INTERRUPTED)
    expect(client.provider_status).to eq(OpenFeature::SDK::ProviderState::STALE)
    expect(client.fetch_boolean_value(flag_key: "bool", default_value: false)).to be(true)
    provider.client.status_provider.update(FeatBit::Status::READY)
    expect(client.provider_status).to eq(OpenFeature::SDK::ProviderState::READY)
    provider.client.send(:broadcast_flag_change, "bool")
    expect(events.last[:flags_changed]).to eq(["bool"])
    provider.shutdown
    provider.client.send(:broadcast_flag_change, "bool")
    expect(events.size).to eq(2)
  end
end
