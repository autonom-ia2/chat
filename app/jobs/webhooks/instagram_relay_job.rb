# Forwards an Instagram webhook to another stack that shares the same Meta app.
# The Page webhook (/bot, Webhooks::FacebookPageController, #2200) reuses it the same way.
#
# Meta allows a single Instagram webhook URL per app, so the stack that receives it relays
# events for Instagram accounts it doesn't know. The original body and X-Hub-Signature-256
# travel untouched: the destination validates Meta's signature with the same app secret.
# RELAY_HEADER marks the request so the destination never relays it again.
class Webhooks::InstagramRelayJob < ApplicationJob
  queue_as :default

  RELAY_HEADER = 'X-Chatwoot-Instagram-Relay'.freeze
  TIMEOUT_SECONDS = 10

  # O corpo leva mensagens de clientes: fora do log do ActiveJob. As tentativas cobrem um deploy da outra stack.
  self.log_arguments = false

  retry_on StandardError, wait: :polynomially_longer, attempts: 10

  def perform(url, raw_body, signature)
    response = HTTParty.post(
      url,
      body: raw_body,
      headers: { 'Content-Type' => 'application/json', 'X-Hub-Signature-256' => signature, RELAY_HEADER => '1' },
      timeout: TIMEOUT_SECONDS
    )
    return if response.success?

    raise "Instagram webhook relay to #{url} failed with HTTP #{response.code}"
  end
end
