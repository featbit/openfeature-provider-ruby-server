# frozen_string_literal: true

require "featbit/openfeature"

env_secret = ENV.fetch("FEATBIT_ENV_SECRET")

provider = FeatBit::OpenFeature::Provider.new(
  FeatBit::Options.new(
    env_secret: env_secret,
    streaming_url: ENV.fetch("FEATBIT_STREAMING_URL", "wss://app-eval.featbit.co"),
    event_url: ENV.fetch("FEATBIT_EVENT_URL", "https://app-eval.featbit.co"),
    start_wait: 5
  )
)

begin
  OpenFeature::SDK.configure { |config| config.set_provider_and_wait(provider) }
  client = OpenFeature::SDK.build_client
  context = OpenFeature::SDK::EvaluationContext.new(
    targeting_key: ENV.fetch("FEATBIT_TARGETING_KEY", "console-user"),
    name: ENV.fetch("FEATBIT_USER_NAME", "Console User")
  )

  loop do
    print "Enter a boolean flag key (or 'exit' to quit): "
    input = $stdin.gets
    break if input.nil?

    flag_key = input.strip
    break if %w[exit quit q].include?(flag_key.downcase)

    if flag_key.empty?
      puts "Flag key cannot be empty."
      next
    end

    details = client.fetch_boolean_details(
      flag_key: flag_key,
      default_value: false,
      evaluation_context: context
    )

    puts "value: #{details.value.inspect}"
    puts "variant: #{details.variant.inspect}"
    puts "reason: #{details.reason.inspect}"
    puts "error_code: #{details.error_code.inspect}"
    puts "error_message: #{details.error_message.inspect}"
    puts "flag_metadata: #{details.flag_metadata.inspect}"
    puts
  end
ensure
  OpenFeature::SDK.shutdown
end
