# Execute only in the approved Rails runtime; typed input travels through stdin.
protocol_stdout = $stdout.dup
protocol_stderr = $stderr.dup
# Boot and at_exit logs must never enter the protocol or expose the input.
$stdout.reopen(File::NULL, 'w')
$stderr.reopen(File::NULL, 'w')

begin
  require_relative '../../config/environment'
  Rails.application.load_runner
  require 'json'

  result = Rails.application.executor.wrap(source: 'application.runner.railties') do
    input = $stdin.read(2.megabytes + 1)
    raise Instagram::Testers::Error, 'session_update_rejected' if input.bytesize > 2.megabytes

    Instagram::Automation::SessionPublisher.new.call(JSON.parse(input)).to_json
  end
  protocol_stdout.write("#{result}\n")
  protocol_stdout.flush
rescue StandardError, ScriptError
  # Exceptions may contain input: never output details or secret payloads.
  protocol_stderr.write("Instagram session publication failed\n")
  protocol_stderr.flush
  exit 2
ensure
  protocol_stdout.close
  protocol_stderr.close
end
