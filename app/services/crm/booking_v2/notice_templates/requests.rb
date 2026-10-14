# Estado dos modelos de aviso pedidos à Meta por uma página (#1272), sem coluna nova. Junta duas fontes:
# - o que a Meta diz (lista de modelos da caixa, `Catalog.meta_states`): em aprovação, aprovado, recusado;
# - o que só a página sabe, em `metadata['notice_template_requests']`: "enviando" (o job ainda não terminou) e "falhou"
#   (a Meta recusou a criação, com o motivo), por caixa. Formato: `{ "<id da caixa>" => { "<aviso>" => { "state" =>
#   "sending" | "failed", "reason" => "...", "at" => iso8601 } } }`.
#
# `start!` marca "enviando" e diz se é para enfileirar: com outro envio em andamento nesta página e caixa, não enfileira
# de novo (clique duplo). Tudo com a linha da página travada (`with_lock`).
class Crm::BookingV2::NoticeTemplates::Requests
  KEY = 'notice_template_requests'.freeze
  # "Enviando" mais velho que isto: o job morreu sem terminar. Vira falha e pode tentar de novo.
  STALE_AFTER = 15.minutes
  Catalog = Crm::BookingV2::NoticeTemplates::Catalog

  def initialize(page:, inbox:)
    @page = page
    @inbox = inbox
  end

  # { "<aviso>" => { "state" => "sending" | "pending" | "approved" | "rejected" | "failed", "reason" => ..., ... } }
  def states
    meta = Catalog.meta_states(@inbox)
    local = local_entries
    Catalog.kinds.each_with_object({}) do |kind, all|
      entry = merged(meta[kind], local[kind])
      all[kind] = entry if entry
    end
  end

  # Avisos que passaram a "enviando" (para o job), ou [] quando já há envio em andamento ou nada a criar.
  def start!(kinds)
    @page.with_lock do
      current = states
      next [] if current.values.any? { |entry| entry['state'] == 'sending' }

      wanted = (Array(kinds).map(&:to_s) & Catalog.kinds).reject { |kind| current[kind] && current[kind]['state'] != 'failed' }
      write(wanted.index_with { { 'state' => 'sending', 'at' => Time.current.iso8601 } }) if wanted.any?
      wanted
    end
  end

  # Fim do envio de um aviso: sem erro, a lista da caixa já responde por ele; com erro, fica "falhou" com o motivo.
  def finish!(kind, error: nil)
    @page.with_lock do
      entry = error ? { kind.to_s => { 'state' => 'failed', 'reason' => error, 'at' => Time.current.iso8601 } } : {}
      write(entry, drop: [kind.to_s])
    end
  end

  private

  def merged(meta, local)
    return local if local && local['state'] == 'sending'
    return meta if meta

    local
  end

  # Entradas desta caixa, com "enviando" velho já como falha.
  def local_entries
    stored_entries.transform_values { |entry| stale?(entry) ? stale_failure : entry }
  end

  def stale?(entry)
    entry['state'] == 'sending' && Time.zone.parse(entry['at'].to_s).to_i < STALE_AFTER.ago.to_i
  end

  def stale_failure
    { 'state' => 'failed', 'reason' => Catalog.text(@inbox.account, 'meta_failed') }
  end

  def stored_entries
    @page.metadata.to_h[KEY].to_h[@inbox.id.to_s].to_h
  end

  def write(entries, drop: [])
    @page.reload
    value = @page.metadata.to_h[KEY].to_h.merge(@inbox.id.to_s => stored_entries.except(*drop).merge(entries))
    @page.update_columns(metadata: @page.metadata.to_h.merge(KEY => value)) # rubocop:disable Rails/SkipsModelValidations
  end
end
