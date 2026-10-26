# A origem de cada card em Números › "De onde vieram os clientes" (#2001, F6 do #1871): o primeiro toque gravado nas
# conversas do card (a principal e as ligadas), pela mesma regra do bloco antigo "De onde vieram" (Crm::Reports::
# OriginMetrics, #1876): o toque sem `source`, gravado antes do campo existir, tem a origem resolvida pela regra do
# próprio toque (Ctwa::CampaignBuilder.source_for); nunca vira anúncio por padrão.
#
# Grupos da tela: anúncio no Facebook ou Instagram (clique para o WhatsApp ou visita do site com sinal da Meta), anúncio
# no Google, seu site ou link marcado, "chegou direto" (nenhum toque) e "outros caminhos" (publicação sem anúncio, outra
# rede, mensagem em massa…). O anúncio do card é o do clique para o WhatsApp (o `source_id` do toque é o id dele).
#
# Uma consulta só, com o toque lido por card no próprio banco (sem o texto do anúncio, `body`).
class Crm::Numeros::Origens::Classificador
  ANUNCIO_META = 'anuncio_meta'.freeze
  DIRETO = 'direto'.freeze
  OUTRAS = 'outras'.freeze
  GRUPOS = { 'meta_ctwa' => ANUNCIO_META, 'meta_paid' => ANUNCIO_META, 'google_ads' => 'google', 'tracked_link' => 'site' }.freeze
  ORIGENS = (GRUPOS.values.uniq + [DIRETO, OUTRAS]).freeze
  # Id de objeto da Meta: só dígitos, de 6 a 30 (a mesma regra do Crm::MetaAds::NameResolver).
  ID_DA_META = (6..30)

  # Duas buscas pela chave de `conversations` (a principal e as ligadas), unidas, com o desempate por fora (#2232): um
  # OR entre as duas fazia o banco ler todas as conversas da conta para cada card. Repetida nas duas, dá o mesmo toque.
  TOQUE_SQL = Arel.sql(<<~SQL.squish)
    (SELECT t.campanha - 'body'
     FROM (SELECT c.id, c.additional_attributes -> 'campaign' AS campanha
           FROM conversations c
           WHERE c.id = crm_cards.conversation_id AND c.account_id = crm_cards.account_id
           UNION ALL
           SELECT c.id, c.additional_attributes -> 'campaign'
           FROM crm_card_conversations cc
           JOIN conversations c ON c.id = cc.conversation_id AND c.account_id = crm_cards.account_id
           WHERE cc.card_id = crm_cards.id AND cc.account_id = crm_cards.account_id) t
     WHERE jsonb_typeof(t.campanha) = 'object'
     ORDER BY NULLIF(t.campanha ->> 'touched_at', '') ASC NULLS FIRST, t.id ASC
     LIMIT 1)
  SQL
  COLUNAS = [:id, :pipeline_id, :title, :created_at, :status, :closed_at, :value_cents, :currency, :owner_id, :stage_id,
             :contact_id, TOQUE_SQL].freeze

  Linha = Struct.new(:id, :pipeline_id, :titulo, :entrou, :venda, :value_cents, :currency, :owner_id, :stage_id,
                     :contact_id, :tipo, :ad_id, :headline, :created_at, :status, keyword_init: true)

  # cards: os cards do mês (Crm::Numeros::Origens::Cards.do_mes); range: o mês (o mesmo da seleção).
  def initialize(cards, range)
    @cards = cards
    @range = range
  end

  def linhas
    @linhas ||= Crm::Card.where(id: ids_dos_cards).pluck(*COLUNAS).map { |colunas| linha(COLUNAS.zip(colunas).to_h) }
  end

  # Ids dos cards de uma origem ou de um anúncio (o "Ver" da Lista).
  def ids_de(origem: nil, anuncio: nil)
    linhas.select { |linha| (origem.blank? || linha.tipo == origem) && (anuncio.blank? || linha.ad_id == anuncio) }.map(&:id)
  end

  private

  # A Lista chega com preload e ordem; para a subconsulta, só os ids.
  def ids_dos_cards
    @cards.unscope(:includes, :preload, :eager_load, :order).select(:id)
  end

  def linha(card)
    toque = ler(card[TOQUE_SQL])
    fonte = fonte_de(toque)
    Linha.new(**card.slice(:id, :pipeline_id, :owner_id, :stage_id, :contact_id, :created_at, :status),
              titulo: card[:title], entrou: @range.cover?(card[:created_at]), venda: venda?(card),
              value_cents: card[:value_cents].to_i, currency: card[:currency].presence || 'BRL',
              tipo: grupo(fonte), ad_id: anuncio_de(fonte, toque), headline: toque&.dig('headline').presence)
  end

  def venda?(card)
    card[:status] == 'won' && card[:closed_at].present? && @range.cover?(card[:closed_at])
  end

  # O jsonb pode chegar como Hash ou, em dado antigo, como texto JSON.
  def ler(toque)
    toque = JSON.parse(toque) if toque.is_a?(String)
    toque.is_a?(Hash) ? toque : nil
  rescue JSON::ParserError
    nil
  end

  def fonte_de(toque)
    return if toque.blank?

    toque['source'].to_s.presence || Ctwa::CampaignBuilder.source_for(toque.symbolize_keys)
  end

  def grupo(fonte)
    return DIRETO if fonte.nil?

    GRUPOS.fetch(fonte, OUTRAS)
  end

  def anuncio_de(fonte, toque)
    return unless fonte == Ctwa::CampaignBuilder::CTWA_SOURCE

    id = toque['source_id'].to_s
    id if ID_DA_META.cover?(id.length) && id.each_char.all? { |char| char.between?('0', '9') }
  end
end
