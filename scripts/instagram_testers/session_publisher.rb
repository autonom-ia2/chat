# Execute only in the approved Rails runtime; typed input travels through stdin.
require 'json'

begin
  input = $stdin.read(2.megabytes + 1)
  raise Instagram::Testers::Error, 'session_update_rejected' if input.bytesize > 2.megabytes

  result = Instagram::Automation::SessionPublisher.new.call(JSON.parse(input))
  $stdout.write(result.to_json)
rescue StandardError
  # Exceptions may contain input: never output details or secret payloads.
  $stderr.write("Instagram session publication failed\n")
  exit 2
end
