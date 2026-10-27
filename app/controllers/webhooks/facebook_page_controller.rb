# Webhook de Página do app da Meta (#2200), no mesmo endereço /bot do Messenger.
#
# A gem facebook-messenger só despacha `entry[].messaging` e descarta `entry[].changes`, onde chegam leads de
# formulário (`leadgen`) e comentários (`feed`). Aqui o POST é conferido (X-Hub-Signature-256) e repartido:
# - `messaging` vai para os handlers da gem (config/initializers/facebook_messenger.rb), como antes;
# - cada `changes[]` vira o job do seu campo, com (page_id, value, time). O job é do recurso que usa o campo e
#   ignora Página que não conhece nesta stack.
# O GET de verificação continua na gem.
#
# O app tem um só endereço de webhook de Página para todas as stacks. A que recebe repassa às outras
# (FB_PAGE_WEBHOOK_RELAY_URLS) todo corpo com `changes` e o `messaging` de Página que não é caixa dela.
class Webhooks::FacebookPageController < ActionController::API
  include MetaTokenVerifyConcern

  CHANGE_JOBS = {
    'leadgen' => 'Webhooks::FacebookLeadgenJob',
    'feed' => 'Webhooks::FacebookFeedJob'
  }.freeze

  before_action :verify_meta_signature!

  def events
    entries = Array(JSON.parse(meta_request_body)['entry'])
    entries.each { |entry| dispatch_entry(entry) }
    relay_to_other_stacks(entries)
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def dispatch_entry(entry)
    Array(entry['messaging']).each { |messaging| Facebook::Messenger::Bot.receive(messaging) }
    Array(entry['changes']).each { |change| enqueue_change(entry, change) }
  end

  def enqueue_change(entry, change)
    job = CHANGE_JOBS[change['field']]&.safe_constantize
    return Rails.logger.info("Facebook page webhook: no job for field #{change['field'].inspect}") if job.nil?

    job.perform_later(entry['id'].to_s, change['value'], entry['time'])
  end

  def relay_to_other_stacks(entries)
    return if relay_urls.empty? || request.headers[::Webhooks::InstagramRelayJob::RELAY_HEADER].present?
    return unless entries.any? { |entry| entry['changes'].present? || !local_page?(entry['id']) }

    relay_urls.each do |url|
      ::Webhooks::InstagramRelayJob.perform_later(url, meta_request_body, request.headers[META_SIGNATURE_HEADER])
    end
  end

  def relay_urls
    @relay_urls ||= GlobalConfigService.load('FB_PAGE_WEBHOOK_RELAY_URLS', '').to_s.split(',').map(&:strip).compact_blank.uniq
  end

  def local_page?(page_id)
    Channel::FacebookPage.exists?(page_id: page_id.to_s)
  end

  def meta_app_secrets
    [
      *page_channels_from_payload.flat_map { |channel| channel_meta_app_secrets(channel) },
      GlobalConfigService.load('FB_APP_SECRET', nil),
      GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    ]
  end

  def page_channels_from_payload
    page_ids = Array(JSON.parse(meta_request_body)['entry']).map { |entry| entry['id'].to_s }
    Channel::FacebookPage.where(page_id: page_ids)
  rescue JSON::ParserError
    []
  end
end
