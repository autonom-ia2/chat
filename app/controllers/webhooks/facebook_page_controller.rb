# Webhook de Página do app da Meta (#2200), no mesmo endereço /bot do Messenger.
#
# A gem facebook-messenger só despacha `entry[].messaging` e descarta `entry[].changes`, onde chegam leads de
# formulário (`leadgen`) e comentários (`feed`). Aqui o POST é conferido (X-Hub-Signature-256) e repartido:
# - `messaging` vai para os handlers da gem (config/initializers/facebook_messenger.rb), como antes;
# - cada `changes[]` vira o job do seu campo, com (page_id, value, time). O job é do recurso que usa o campo e
#   ignora Página que não conhece nesta stack. Se o job tiver `webhook_value`, o `value` passa por ele antes de virar
#   argumento: o Sidekiq guarda os argumentos em claro no Redis (fila, retry, dead set), e o comentário (`feed`, #2197)
#   vai só com os ids.
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

    value = job.respond_to?(:webhook_value) ? job.webhook_value(change['value']) : change['value']
    job.perform_later(entry['id'].to_s, value, entry['time'])
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

  # Channel::FacebookPage não guarda segredo próprio: valem os do app (FB_APP_SECRET e WHATSAPP_APP_SECRET, o mesmo app
  # do Entrar com Facebook dos anúncios).
  def meta_app_secrets
    [GlobalConfigService.load('FB_APP_SECRET', nil), GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)]
  end
end
