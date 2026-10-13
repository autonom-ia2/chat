# Aviso da Meta sobre um modelo (#1337): situação (`message_template_status_update`), qualidade
# (`message_template_quality_update`) ou tipo (`template_category_update`). O aviso vem por WABA (`entry.id`), sem número:
# muda o modelo em todas as caixas Cloud daquela WABA, só pelo `ChannelList`, sem chamar a Graph. Formatos conferidos na
# referência de webhooks da Meta (developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/…).
#
# - O modelo é achado pelo id da Meta (o aviso traz o idioma como `pt-BR`, a lista guarda `pt_BR`).
# - Modelo que a caixa ainda não tem (criado no WhatsApp Manager) ou evento sem situação equivalente na lista
#   (FLAGGED, LOCKED, UNARCHIVED): nada é inventado, o sync da caixa é pedido.
# - Ordem: cada entrada guarda em `webhook_event_times` a hora (`entry.time`) do último aviso aplicado de cada tipo. Aviso
#   mais antigo não regride; repetido não muda nada; dois diferentes no mesmo segundo (ordem incerta) pedem o sync. Aviso
#   anterior ao último sync da caixa não muda a lista e pede outro sync: o carimbo do sync é gravado já no começo da busca
#   (também quando ela falha) e uma entrada mexida durante a busca fica como estava (`ChannelList.replace!`); o sync novo
#   traz a situação certa.
class Whatsapp::Templates::WebhookEvent
  FIELD_KINDS = {
    'message_template_status_update' => 'status',
    'message_template_quality_update' => 'quality',
    'template_category_update' => 'category'
  }.freeze
  # Evento → situação da lista (os valores do `status` da Graph). REINSTATED: "pode ser enviado de novo".
  STATUS_BY_EVENT = %w[APPROVED PENDING REJECTED PAUSED DISABLED IN_APPEAL LIMIT_EXCEEDED PENDING_DELETION ARCHIVED DELETED]
                    .index_with(&:itself).merge('REINSTATED' => 'APPROVED').freeze
  TIMES_KEY = 'webhook_event_times'.freeze
  # Resultados em que a lista pode estar atrás da Meta: pedem o sync da caixa.
  SYNC_OUTCOMES = %w[missing needs_sync before_last_sync].freeze

  def initialize(waba_id:, field:, time:, value:)
    @waba_id = waba_id.to_s
    @kind = FIELD_KINDS[field]
    @time = time.to_i
    @value = value.to_h.stringify_keys
  end

  def perform
    return log('ignored') if @kind.nil? || @waba_id.blank? || template_id.blank? || @time.zero?

    channels = Channel::Whatsapp.where(provider: 'whatsapp_cloud').where("provider_config ->> 'business_account_id' = ?", @waba_id)
    log('no_channel') if channels.none?
    channels.find_each { |channel| apply(channel) }
  end

  private

  def template_id
    @value['message_template_id'].to_s
  end

  def apply(channel)
    @outcome = nil
    result = Whatsapp::Templates::ChannelList.change!(channel, { 'id' => template_id }) { |entry| updated_entry(channel, entry) }
    outcome = result == :changed ? 'changed' : (@outcome || result.to_s)
    Channels::Whatsapp::TemplatesSyncJob.perform_later(channel) if SYNC_OUTCOMES.include?(outcome)
    log(outcome, channel)
  end

  # Lido com a trava da linha (dentro do `change!`): um sync que gravou entre a busca das caixas e a trava conta.
  def synced_after_event?(channel)
    last_sync = channel.class.where(id: channel.id).pick(:message_templates_last_updated)
    last_sync.present? && Time.zone.at(@time) < last_sync
  end

  # Entrada nova ou nil (com o motivo em @outcome).
  def updated_entry(channel, entry)
    return outcome!('before_last_sync') if synced_after_event?(channel)

    changes = changes_for(entry)
    return outcome!('needs_sync') if changes.nil?

    last = entry.dig(TIMES_KEY, @kind).to_i
    return outcome!('stale') if @time < last
    return outcome!('needs_sync') if @time == last && entry.slice(*changes.keys) != changes

    entry.merge(changes, TIMES_KEY => entry[TIMES_KEY].to_h.merge(@kind => @time))
  end

  def outcome!(name)
    @outcome = name
    nil
  end

  def changes_for(entry)
    case @kind
    when 'status' then status_changes
    when 'quality' then quality_changes(entry)
    else category_changes
    end
  end

  def status_changes
    status = STATUS_BY_EVENT[@value['event'].to_s]
    return if status.nil?
    return { 'status' => status } unless status == 'REJECTED' && @value['reason'].present?

    { 'status' => status, 'rejected_reason' => @value['reason'] }
  end

  # `quality_score` do sync é { score, date }: troca a nota e mantém o resto.
  def quality_changes(entry)
    score = @value['new_quality_score'].presence
    return if score.nil?

    { 'quality_score' => entry['quality_score'].to_h.merge('score' => score) }
  end

  # Aviso de mudança em 24 h traz `correct_category` (o `new_category` dele é o tipo atual): só guarda o previsto.
  # Mudança feita traz `previous_category` e `new_category`.
  def category_changes
    return { 'correct_category' => @value['correct_category'] } if @value['correct_category'].present?
    return if @value['new_category'].blank? || @value['previous_category'].blank?

    { 'category' => @value['new_category'], 'previous_category' => @value['previous_category'] }
  end

  # Só ids e situação no log.
  def log(result, channel = nil)
    Rails.logger.info "[whatsapp][templates] webhook kind=#{@kind || 'unknown'} waba_id=#{@waba_id} template_id=#{template_id} " \
                      "event=#{@value['event'] || @value['new_quality_score'] || @value['new_category']} " \
                      "channel_id=#{channel&.id} result=#{result}"
  end
end
