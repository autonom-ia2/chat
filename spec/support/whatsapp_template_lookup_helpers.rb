# #1329: the WhatsApp campaign dispatch asks Meta for the template (Whatsapp::Templates::MetaLookup)
# before sending. Specs stub that GET: `answer` is either the templates Meta returns or an HTTP status
# (e.g. 503) to exercise the fallback to channel.message_templates. Returns the requests made.
module WhatsappTemplateLookupHelpers
  TEMPLATE_LOOKUP = ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') }

  def stub_meta_template_lookup(answer = 503)
    requests = []
    stub_request(:get, TEMPLATE_LOOKUP).to_return do |request|
      requests << request
      if answer.is_a?(Integer)
        { status: answer, headers: { 'Content-Type' => 'application/json' }, body: { error: { message: 'unavailable' } }.to_json }
      else
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: answer }.to_json }
      end
    end
    requests
  end
end

RSpec.configure do |config|
  config.include WhatsappTemplateLookupHelpers
end
