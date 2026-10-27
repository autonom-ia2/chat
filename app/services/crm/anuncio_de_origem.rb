# Quem vê qual anúncio trouxe o cliente (#2271; decisões do Rodrigo, 27/10). A regra é a do valor de venda (#2075,
# Crm::ValorDeVenda.ve?) e da leitura de relacionamentos (Relationships::RecordPermissions): vê o administrador, o
# agente sem função personalizada e a função com `meta_ads_view` ou `meta_ads_manage` (manage implica view,
# Enterprise::AccountUser#permission_granted?). Só a função personalizada sem a chave deixa de ver: ela vê que o cliente
# veio de anúncio, por onde e quando, como já acontece com o gasto.
#
# "Anúncio" é o anúncio que trouxe o card, não só o da Meta: Google Ads e TikTok Ads ficam escondidos junto (decisão do
# Rodrigo, 27/10). É de anúncio pelo `source` gravado ou pela regra de "pago" do próprio Ctwa::CampaignBuilder.source_for,
# refeita sobre o toque sem origem, de link ou de publicação (pega o toque antigo). Visita do site com UTM fora de
# `PAID_UTM_MEDIUMS` (ex.: utm_medium=ads) continua visita do site. Toque que não é anúncio (publicação, link do site,
# divulgação por WhatsApp, e-mail, SMS ou chat do site) não muda.
#
# O toque de anúncio sai sem o que identifica o anúncio: título, texto, nomes de campanha/grupo/anúncio, prévia,
# miniatura, endereço, UTMs, ids de clique e o id do anúncio. Fica a origem (`source`), `source_type` e `touched_at`
# (no card, também `conversation_id`), com `ad_hidden: true`.
#
#   Crm::AnuncioDeOrigem.ve?(account_user)                 -> true | false
#   Crm::AnuncioDeOrigem.para_quem_nao_ve(toque, item)     -> o item do card, sem o anúncio quando o toque é de anúncio
#   Crm::AnuncioDeOrigem.atributos_para(account_user, attrs) -> additional_attributes da conversa como a pessoa pode ver
#   Crm::AnuncioDeOrigem.oculta_toque(toque)               -> o toque gravado (chaves em texto), sem o anúncio
#   Crm::AnuncioDeOrigem.ids_de_anuncio(account, ids)      -> os ids, dentre `ids`, que são de anúncio na conta
#
# O balão do referral na mensagem (content_attributes da MENSAGEM, WhatsappReferral.vue) fica como está.
module Crm::AnuncioDeOrigem
  CHAVE = 'meta_ads_view'.freeze
  FONTES_DE_ANUNCIO = %w[meta_ctwa meta_paid google_ads tiktok_ads].freeze
  CAMPOS_QUE_FICAM = %i[source source_type touched_at conversation_id].freeze
  CAMPOS_DO_TOQUE_QUE_FICAM = %w[source_type touched_at].freeze
  # Origens em que a regra de "pago" é refeita sobre o toque: sem origem gravada, link e publicação.
  ORIGENS_REFEITAS = ['', 'tracked_link', Ctwa::CampaignBuilder::ORGANIC_SOURCE].freeze

  # Os toques gravados (a lista e a origem) das conversas da conta com um dos ids. O espelho `campaign_source_ids` filtra
  # primeiro, pelo índice trigram (mesma sonda do filtro do CRM).
  TOQUES_SQL = <<~SQL.squish.freeze
    SELECT DISTINCT toque::text
    FROM conversations
    CROSS JOIN LATERAL jsonb_array_elements(
      (CASE WHEN jsonb_typeof(conversations.additional_attributes -> 'campaign_touches') = 'array'
            THEN conversations.additional_attributes -> 'campaign_touches' ELSE '[]'::jsonb END) ||
      (CASE WHEN jsonb_typeof(conversations.additional_attributes -> 'campaign') = 'object'
            THEN jsonb_build_array(conversations.additional_attributes -> 'campaign') ELSE '[]'::jsonb END)
    ) AS toque
    WHERE conversations.account_id = :account_id
      AND conversations.additional_attributes ->> 'campaign_source_ids' ILIKE ANY (ARRAY[:sondas])
      AND toque ->> 'source_id' IN (:ids)
  SQL

  module_function

  def ve?(account_user)
    return false if account_user.blank?
    return true if account_user.administrator? || account_user.custom_role_id.blank?

    account_user.permission_granted?(CHAVE)
  end

  # toque: o toque gravado na conversa (chaves em texto); item: o mesmo toque já no formato do card.
  def para_quem_nao_ve(toque, item)
    fonte = fonte_de_anuncio(toque)
    return item if fonte.blank?

    item.to_h { |campo, valor| [campo, CAMPOS_QUE_FICAM.include?(campo) ? valor : nil] }
        .merge(source: fonte, ad_hidden: true)
  end

  def oculta_toque(toque)
    return toque unless toque.is_a?(Hash)

    fonte = fonte_de_anuncio(toque)
    return toque if fonte.blank?

    toque.slice(*CAMPOS_DO_TOQUE_QUE_FICAM).merge('source' => fonte, 'ad_hidden' => true)
  end

  # additional_attributes da conversa (chaves em texto, como vêm do banco): para quem não vê, a origem (`campaign`), a
  # lista (`campaign_touches`) e o espelho de ids (`campaign_source_ids`) saem sem o anúncio. O resto não muda.
  # Sem account_user, quem lê não é uma pessoa da conta (robô ou integração pelo token do robô, como o n8n): a regra é
  # de função personalizada, e a resposta segue inteira, como antes.
  def atributos_para(account_user, atributos)
    return atributos unless atributos.is_a?(Hash) && com_toques?(atributos)
    return atributos if account_user.blank? || ve?(account_user)

    oculta_atributos(atributos)
  end

  # O push_event_data da conversa (notificação): o mesmo, com os additional_attributes como a pessoa pode ver.
  def evento_para(account_user, dados)
    return dados unless dados.is_a?(Hash) && dados[:additional_attributes].is_a?(Hash)

    dados.merge(additional_attributes: atributos_para(account_user, dados[:additional_attributes].stringify_keys))
  end

  def com_toques?(atributos)
    atributos.key?('campaign') || atributos.key?('campaign_touches')
  end

  def oculta_atributos(atributos)
    ocultos = {
      'campaign' => oculta_toque(atributos['campaign']),
      'campaign_touches' => Array(atributos['campaign_touches']).map { |toque| oculta_toque(toque) },
      'campaign_source_ids' => Array(atributos['campaign_source_ids']) - ids_de_anuncio_nos(atributos)
    }
    atributos.merge(ocultos.slice(*atributos.keys))
  end

  def ids_de_anuncio_nos(atributos)
    toques = Array(atributos['campaign_touches']) + [atributos['campaign']]
    toques.select { |toque| toque.is_a?(Hash) && fonte_de_anuncio(toque) }.pluck('source_id')
  end

  def ids_de_anuncio(account, ids)
    return [] if ids.blank?

    sondas = ids.map { |id| "%\"#{ActiveRecord::Base.sanitize_sql_like(id)}\"%" }
    sql = ActiveRecord::Base.sanitize_sql_array([TOQUES_SQL, { account_id: account.id, sondas: sondas, ids: ids }])
    ActiveRecord::Base.connection.select_values(sql).filter_map do |texto|
      toque = JSON.parse(texto)
      toque['source_id'] if fonte_de_anuncio(toque)
    end.uniq
  end

  # A origem de anúncio do toque, ou nil. Vale o `source` gravado e também a regra de hoje do próprio código para
  # "pago" (Ctwa::CampaignBuilder.source_for: ctwa_clid ou source_type 'ad', gclid, ttclid, fbclid ou as UTMs da Meta
  # pagas), refeita sobre o toque: o toque gravado antes da regra mudar (UTMs do #1011, `source` que não existia)
  # ficou com outra origem, mas carrega os mesmos sinais. A regra só é refeita sobre o toque sem origem ou gravado como
  # link ou publicação, que é onde a regra de "pago" cai quando não vê o sinal. Origem explícita que não é anúncio
  # (divulgação por WhatsApp, e-mail, SMS, chat do site) fica como foi gravada, mesmo com fbclid ou UTM da Meta.
  def fonte_de_anuncio(toque)
    gravada = toque['source'].to_s
    return gravada if FONTES_DE_ANUNCIO.include?(gravada)
    return unless ORIGENS_REFEITAS.include?(gravada)

    pela_regra = Ctwa::CampaignBuilder.source_for(toque.symbolize_keys)
    pela_regra if FONTES_DE_ANUNCIO.include?(pela_regra)
  end
end
