# FeatBit OpenFeature Provider for Ruby

Use [FeatBit](https://featbit.co) feature flags through the
[OpenFeature Ruby SDK](https://openfeature.dev/docs/reference/sdks/server/ruby/).
Evaluation and analytics are handled by the [FeatBit Ruby Server SDK](https://github.com/featbit/featbit-ruby-server-sdk).

## Requirements and installation

Ruby 3.4 or newer. This provider uses `openfeature-sdk ~> 0.6.5` and
`featbit-server-sdk ~> 0.1.0`.

Add the provider to your Gemfile:

```ruby
gem "featbit-openfeature-provider", "~> 0.1.0"
```

Run `bundle install`. For local development, use `path:` pointing at this checkout.

## Quick start

```ruby
require "featbit/openfeature"

provider = FeatBit::OpenFeature::Provider.new(
  FeatBit::Options.new(
    env_secret: ENV.fetch("FEATBIT_ENV_SECRET"),
    streaming_url: ENV.fetch("FEATBIT_STREAMING_URL", "wss://app-eval.featbit.co"),
    event_url: ENV.fetch("FEATBIT_EVENT_URL", "https://app-eval.featbit.co"),
    start_wait: 5
  )
)

# Raises OpenFeature::SDK::ProviderInitializationError if FeatBit is not ready.
OpenFeature::SDK.configure { |config| config.set_provider_and_wait(provider) }
client = OpenFeature::SDK.build_client
context = OpenFeature::SDK::EvaluationContext.new(
  targeting_key: "user-123", name: "Alice", country: "FR", plan: "pro"
)

enabled = client.fetch_boolean_value(
  flag_key: "new-checkout", default_value: false, evaluation_context: context
)

details = client.fetch_boolean_details(
  flag_key: "new-checkout", default_value: false, evaluation_context: context
)
puts "value=#{enabled} variant=#{details.variant} reason=#{details.reason} error=#{details.error_code}"

# Call during graceful application shutdown to close connections and flush events.
OpenFeature::SDK.shutdown
```

Create one provider per application process and reuse the OpenFeature client.
For prefork servers, create the provider in each worker after fork.
The FeatBit client starts during provider construction and waits up to `start_wait`.
OpenFeature calls `init` to check readiness; `config.set_provider(provider)` offers
nonblocking OpenFeature registration if you do not need to wait for registration.

An existing client can be supplied with
`FeatBit::OpenFeature::Provider.new(client: featbit_client)`. The provider takes
ownership: replacement or OpenFeature shutdown closes that client. Do not share
one FeatBit client between independently managed providers. A closed provider
cannot restart; construct a new instance.

## Evaluation context

| OpenFeature field | FeatBit user field |
| --- | --- |
| `targeting_key` | Required non-empty string user key |
| `name` | Optional string user name |
| Other fields | Custom attributes, with their values preserved |

Missing or empty targeting keys return `TARGETING_KEY_MISSING`. Non-string keys,
non-string names, and unsupported context objects return `INVALID_CONTEXT`.
The provider does not invent anonymous identities or use `key` as a fallback.
Built-in FeatBit user properties retain the SDK's precedence over custom attributes.
Contexts are not modified. Custom attribute matching and analytics serialization
follow the FeatBit SDK's behavior; use scalar attributes for targeting rules.

OpenFeature merges API, client, transaction, and invocation contexts before calling
the provider. A targeting key may therefore be set at any of those scopes.

## Values and resolution details

The provider supports `fetch_boolean_value`, `fetch_string_value`,
`fetch_number_value`, `fetch_integer_value`, `fetch_float_value`, and
`fetch_object_value`, plus OpenFeature's corresponding `fetch_*_details` methods.
Objects may be hashes or arrays. Integer evaluation truncates numeric values toward
zero; float evaluation converts numeric values to Float. Incompatible types return
the caller's default with `TYPE_MISMATCH`.

Successful details include the FeatBit variation ID as `variant`, plus
`featbit.reason`, `featbit.flag_name` (when available), and `featbit.in_experiment`
in flag metadata.

| FeatBit reason/error | OpenFeature reason/error |
| --- | --- |
| Flag off | `DISABLED` |
| User target or rule match | `TARGETING_MATCH` |
| Fallthrough | `DEFAULT` |
| Client not ready | `ERROR` / `PROVIDER_NOT_READY` |
| Flag not found | `ERROR` / `FLAG_NOT_FOUND` |
| Wrong type | `ERROR` / `TYPE_MISMATCH` |
| User not specified | `ERROR` / `TARGETING_KEY_MISSING` |
| Other evaluation errors | `ERROR` / `GENERAL` |

Errors return the caller's default without a variant. FeatBit does not expose a
separate parse error category, so malformed flag evaluation errors map to `GENERAL`.
Evaluation analytics are produced by FeatBit's `variation_detail`; a successful
FeatBit evaluation can record an event even if the provider subsequently rejects
its type.

## Events and tracking

The provider forwards FeatBit readiness, interrupted synchronization, and flag
changes as `PROVIDER_READY`, `PROVIDER_STALE`, and
`PROVIDER_CONFIGURATION_CHANGED` (with `flags_changed`). Failed or closed clients
emit `PROVIDER_ERROR`. Cached flags remain available during synchronization
interruptions. Shutdown removes the provider's listeners.

```ruby
client.add_handler(OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED) do |event|
  puts event[:flags_changed].inspect
end

client.track(
  "purchase",
  evaluation_context: context,
  tracking_event_details: OpenFeature::SDK::TrackingEventDetails.new(value: 19.95)
)
```

Tracking requires a valid targeting key. Omitted metric values default to `1.0`.
Extra tracking fields are ignored because the FeatBit tracking API accepts only a
user, event name, and numeric value. Invalid tracking contexts produce no event.

## Offline use

```ruby
require "json"

provider = FeatBit::OpenFeature::Provider.new(
  FeatBit::Options.new(offline: true, bootstrap: JSON.parse(File.read("bootstrap.json")))
)
```

Supply a full FeatBit data-sync payload containing feature flags and segments.
Offline mode disables networking and analytics. Without initialized bootstrap
data the provider reports `PROVIDER_NOT_READY`.

## Console example

The console example evaluates a boolean flag against a FeatBit environment:

```sh
FEATBIT_ENV_SECRET="your-environment-secret" bundle exec ruby examples/console.rb
```

Enter a boolean flag key at the prompt to evaluate it. The prompt repeats so
multiple flags can be evaluated in one session. Enter `exit`, `quit`, or `q`
to stop the application.

Set `FEATBIT_TARGETING_KEY` to evaluate for a different user. The streaming and
event URLs default to FeatBit Cloud and can be overridden with
`FEATBIT_STREAMING_URL` and `FEATBIT_EVENT_URL`.

## Development

```sh
bundle install
bundle exec rake
gem build featbit-openfeature-provider.gemspec
```

Tests run against the released SDK gems with real offline FeatBit evaluation,
including OpenFeature context merging, defaults, details, events, and tracking.
No FeatBit service or environment secret is required.
