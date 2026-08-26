# Vig.ia telemetry

## Decision

Implement centralized, opt-in telemetry for HTTP requests and ActiveJob executions using a small internal Ruby client.

## Scope

- `VIGIA_ENABLED=false` keeps the current behavior.
- The API key is read from `VIGIA_API_KEY`; no secret is stored in code.
- HTTP instrumentation is placed in Rack middleware to avoid touching individual controllers.
- Job instrumentation is placed in `ApplicationJob` to avoid changing job classes.
- Payloads intentionally exclude request headers, cookies, bodies, query strings, job arguments and message content.

## Validation

- Targeted RSpec command attempted:
  `bundle exec rspec spec/lib/vigia/client_spec.rb spec/lib/vigia/instrumentation_spec.rb spec/middleware/vigia/request_middleware_spec.rb spec/jobs/application_job_vigia_spec.rb`
- Local run was blocked because this shell only has macOS Ruby 2.6 and is missing Bundler 2.5.16 for the project lockfile. The repository requires Ruby 3.4.4.
