# A coorte do painel sem conexão (Anúncios sem login, #1960): as mesmas regras do Panel::Cohort, lidas direto dos
# toques gravados na conversa (`campaign_touches`, Ctwa::CampaignBuilder) em vez das ligações Crm::MetaAdLink, que
# só são gravadas para conta com conexão. Assim o painel mostra os últimos 90 dias logo que a flag liga, sem carga
# nenhuma gravada em produção.
#
# Toque de anúncio da Meta e o anúncio dele seguem o Links::Linker: clique para o WhatsApp, ou página do site com
# sinal da Meta; o anúncio é o ID que veio no toque. Sem token não há cache de nomes, então o "anúncio pelo nome
# dentro da campanha" (certeza `ad_name`) fica de fora. Conversa antiga, gravada antes da lista de toques, só tem a
# origem (`campaign`): vale como um toque no início da conversa, a mesma regra de Ctwa::CampaignBuilder.existing_touches.
# Só os toques são lidos (sem o texto do anúncio, `body`), uma vez por coorte.
class Crm::MetaAds::Panel::WhatsappCohort < Crm::MetaAds::Panel::Cohort
  TOUCHES_SQL = Arel.sql("conversations.additional_attributes -> 'campaign_touches'")
  ORIGIN_SQL = Arel.sql("(conversations.additional_attributes -> 'campaign') - 'body'")
  COLUMNS = [:id, :created_at, TOUCHES_SQL, ORIGIN_SQL].freeze
  BATCH_SIZE = 500

  # { conversation_id => [ad_id ou nil, touched_at] }, como Cohort#touches.
  def touches
    @touches ||= meta_touches.sort_by { |row| row[2] }.each_with_object({}) do |(id, ad, at), all|
      all[id] = [ad, at] if all[id].nil? || all[id].first.nil?
    end
  end

  # { conversation_id => primeiro toque de anúncio no período }: o início do tempo de resposta (Panel::ResponseTime).
  def starts
    @starts ||= meta_touches.each_with_object({}) { |(id, _ad, at), all| all[id] = at if all[id].nil? || at < all[id] }
  end

  # Houve algum toque de anúncio no período? Lê aos poucos e para no primeiro (a tela vazia só precisa do sim/não).
  def any?
    candidates.in_batches(of: BATCH_SIZE).any? do |batch|
      batch.pluck(*COLUMNS).any? { |columns| conversation_rows(*columns).any? }
    end
  end

  # Horário do primeiro toque de anúncio no período (#2011, "desde o primeiro anúncio"). Lê em lotes pela ordem de
  # criação e para quando a conversa do lote já é mais nova que o toque achado: toque vem sempre depois da conversa.
  def first_touch_at
    first = nil
    candidates.in_batches(of: BATCH_SIZE) do |batch|
      rows = batch.pluck(*COLUMNS)
      break if first && rows.map { |row| row[1] }.min > first

      found = rows.flat_map { |columns| conversation_rows(*columns) }.map(&:last).min
      first = [first, found].compact.min
    end
    first
  end

  private

  # [[conversation_id, ad_id ou nil, touched_at], ...] dos toques de anúncio no período.
  def meta_touches
    @meta_touches ||= candidates.pluck(*COLUMNS).flat_map { |columns| conversation_rows(*columns) }
  end

  # Gravar um toque atualiza a conversa, então quem teve toque no período tem updated_at dentro dele.
  def candidates
    Conversation.where(account_id: @account_id, updated_at: @range.begin..)
                .where("conversations.additional_attributes ?| array['campaign_touches', 'campaign']")
  end

  def conversation_rows(conversation_id, created_at, list, origin)
    touches = list.is_a?(Array) ? list : legacy_touches(origin, created_at)
    touches.filter_map { |touch| row(conversation_id, touch) }
  end

  def legacy_touches(origin, created_at)
    origin.is_a?(Hash) ? [origin.merge('touched_at' => origin['touched_at'] || created_at.utc.iso8601)] : []
  end

  def row(conversation_id, touch)
    return unless Crm::MetaAds::Links::Linker.meta_touch?(touch)

    touched_at = parse_time(touch['touched_at'])
    return unless touched_at && @range.cover?(touched_at)

    [conversation_id, Crm::MetaAds::TouchEnricher.ids_by_type(touch)['ad']&.first, touched_at]
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
