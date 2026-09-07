# frozen_string_literal: true

require "spec_helper"

RSpec.describe FeatBit::OpenFeature::DetailsConverter do
  { client_not_ready: "PROVIDER_NOT_READY", flag_not_found: "FLAG_NOT_FOUND",
    user_not_specified: "TARGETING_KEY_MISSING", wrong_type: "TYPE_MISMATCH",
    error: "GENERAL", future_error: "GENERAL" }.each do |kind, code|
    it "maps #{kind} before checking the fallback type" do
      detail = FeatBit::EvaluationDetail.new(value: nil, error_kind: kind, error_message: "failure")
      result = described_class.convert(detail, :boolean, false)
      expect(result.value).to be(false)
      expect(result.error_code).to eq(code)
      expect(result.error_message).to eq("failure")
      expect(result.variant).to be_nil
    end
  end

  it "preserves unknown reasons as metadata" do
    detail = FeatBit::EvaluationDetail.new(value: "value", reason: "future reason", variation_id: "v")
    result = described_class.convert(detail, :string, "")
    expect(result.reason).to eq("UNKNOWN")
    expect(result.flag_metadata["featbit.reason"]).to eq("future reason")
  end
end
