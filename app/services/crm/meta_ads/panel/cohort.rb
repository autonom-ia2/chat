# As conversas que vieram de anúncio no período e o que aconteceu com elas no CRM (#1088, F3a).
#
# Cada conversa conta para um anúncio só: o do primeiro toque do período que tem anúncio identificado (sem
# nenhum, conta no total mas em nenhum anúncio). Os cards saem da conversa pelas ligações do CRM
# (crm_card_conversations) e pelo card principal (crm_cards.conversation_id).
#
# Proposta: card aberto numa etapa que a pessoa marcou como "opportunity" ou "negotiation" (passo 4), ou card
# ganho. Venda: card ganho. É uma coorte — "das conversas que chegaram no período, o que virou" —, não o que
# fechou no período.
#
# O card leva o dono (`owner_id`, para o Crm::ValorDeVenda.ve_o_card?) e quando fechou (`closed_at`, a ordem das vendas
# para quem não vê o valor, #2075).
class Crm::MetaAds::Panel::Cohort
  QUOTE_TYPES = %w[opportunity negotiation].freeze

  Card = Struct.new(:id, :title, :status, :value, :stage_type, :stage_name, :conversation_id, :ad_id, :waiting_since,
                    :owner_id, :closed_at, keyword_init: true) do
    def quote?
      status == 'won' || (status == 'open' && QUOTE_TYPES.include?(stage_type))
    end

    def sale?
      status == 'won'
    end

    def open?
      status == 'open'
    end

    def lost?
      status == 'lost'
    end
  end

  def initialize(account_id, range)
    @account_id = account_id
    @range = range
  end

  # { conversation_id => ad_id ou nil }
  def conversation_ads
    @conversation_ads ||= touches.transform_values(&:first)
  end

  # { conversation_id => [ad_id ou nil, touched_at] }: o toque que decide o anúncio da conversa. O horário é o
  # desse toque, para o "por dia" do anúncio (F3b) somar exatamente as conversas que o painel conta para ele.
  def touches
    @touches ||= Crm::MetaAdLink.where(account_id: @account_id, touched_at: @range).order(:touched_at)
                                .pluck(:conversation_id, :ad_id, :touched_at)
                                .each_with_object({}) { |(id, ad, at), all| all[id] = [ad, at] if all[id].nil? || all[id].first.nil? }
  end

  def cards
    @cards ||= load_cards
  end

  # Horário do primeiro toque de anúncio no período (#2011, "desde o primeiro anúncio").
  def first_touch_at
    Crm::MetaAdLink.where(account_id: @account_id, touched_at: @range).minimum(:touched_at)
  end

  # Início de cada conversa para o tempo de resposta; nil: o Panel::ResponseTime lê das ligações Crm::MetaAdLink.
  def starts
    nil
  end

  private

  def load_cards
    links = card_links
    return [] if links.empty?

    # #2084: card de contato fora do funil (parceiro, não é negócio) não conta como proposta nem venda do anúncio.
    Crm::Relacao.cards_do_funil(Account.find(@account_id)).where(id: links.keys).includes(:stage)
                .map { |card| card_row(card, links[card.id]) }
  end

  def card_row(card, conversation_id)
    Card.new(id: card.id, title: card.title, status: card.status, value: card.value_cents / 100.0,
             stage_type: card.stage&.metadata.to_h['funnel_stage_type'], stage_name: card.stage&.name, conversation_id: conversation_id,
             ad_id: conversation_ads[conversation_id], waiting_since: card.last_message_at || card.entered_stage_at,
             owner_id: card.owner_id, closed_at: card.closed_at)
  end

  # { card_id => conversation_id }, preferindo a conversa que tem anúncio identificado.
  def card_links
    ids = conversation_ads.keys
    return {} if ids.empty?

    pairs = Crm::CardConversation.where(account_id: @account_id, conversation_id: ids).pluck(:card_id, :conversation_id) +
            Crm::Card.where(account_id: @account_id, conversation_id: ids).pluck(:id, :conversation_id)
    pairs.each_with_object({}) do |(card_id, conversation_id), all|
      all[card_id] = conversation_id if all[card_id].nil? || conversation_ads[all[card_id]].nil?
    end
  end
end
