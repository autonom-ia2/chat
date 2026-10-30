# Quem vê qual anúncio trouxe o cliente (#2271; decisões do Rodrigo, 27/10). A regra é a do valor de venda (#2075,
# Crm::ValorDeVenda.ve?) e da leitura de relacionamentos (Relationships::RecordPermissions): vê o administrador, o
# agente sem função personalizada e a função com `meta_ads_view` ou `meta_ads_manage` (manage implica view,
# Enterprise::AccountUser#permission_granted?). Só a função personalizada sem a chave deixa de ver: ela vê que o cliente
# veio de anúncio, por onde e quando, como já acontece com o gasto. Fora das pessoas, vê tudo o robô (token do AgentBot)
# e a chamada interna que se declara (`interno: true`); sem identidade, não vê (ve_no_contexto?). Super admin ou usuário
# sem AccountUser na conta também não vê. Contato e widget (token do contact_inbox) continuam recebendo o próprio anúncio.
#
# "Anúncio" é o anúncio que trouxe o card, não só o da Meta: Google Ads e TikTok Ads ficam escondidos junto (decisão do
# Rodrigo, 27/10). É de anúncio pelo `source` gravado ou pela regra de "pago" do próprio Ctwa::CampaignBuilder.source_for,
# refeita sobre o toque sem origem, de link ou de publicação (pega o toque antigo). Visita do site com UTM fora de
# `PAID_UTM_MEDIUMS` (ex.: utm_medium=ads) continua visita do site. Toque que não é anúncio (publicação, link do site,
# divulgação por WhatsApp, e-mail, SMS ou chat do site) não muda. Um id que foi anúncio em qualquer toque conta como
# anúncio (Crm::AnuncioDeOrigem::Ids).
#
# O toque de anúncio sai sem o que identifica o anúncio: título, texto, nomes de campanha/grupo/anúncio, prévia,
# miniatura, endereço, UTMs, ids de clique e o id do anúncio. Fica a origem (`source`), `source_type` e `touched_at`
# (no card, também `conversation_id`), com `ad_hidden: true`.
#
#   Crm::AnuncioDeOrigem.ve?(account_user)                          -> a pessoa vê?
#   Crm::AnuncioDeOrigem.ve_no_contexto?(user, account_user, interno: false) -> quem lê (pessoa, robô, interno) vê?
#   Crm::AnuncioDeOrigem.para_quem_nao_ve(toque, item)              -> o item do card, sem o anúncio
#   Crm::AnuncioDeOrigem.atributos_para(user, account_user, attrs)  -> additional_attributes da conversa como quem lê vê
#   Crm::AnuncioDeOrigem.oculta_toque(toque)                        -> o toque gravado (chaves em texto), sem o anúncio
#
# O balão do referral na mensagem (content_attributes da MENSAGEM, WhatsappReferral.vue) fica como está.
module Crm::AnuncioDeOrigem
  CHAVE = 'meta_ads_view'.freeze
  FONTES_DE_ANUNCIO = %w[meta_ctwa meta_paid google_ads tiktok_ads].freeze
  CAMPOS_QUE_FICAM = %i[source source_type touched_at conversation_id].freeze
  CAMPOS_DO_TOQUE_QUE_FICAM = %w[source_type touched_at].freeze
  # Origens em que a regra de "pago" é refeita sobre o toque: sem origem gravada, link e publicação.
  ORIGENS_REFEITAS = ['', 'tracked_link', Ctwa::CampaignBuilder::ORGANIC_SOURCE].freeze

  module_function

  def ve?(account_user)
    return false if account_user.blank?
    return true if account_user.administrator? || account_user.custom_role_id.blank?

    account_user.permission_granted?(CHAVE)
  end

  # Quem lê: a pessoa (User + AccountUser) segue ve?; o robô (Current.user AgentBot, token do robô) vê tudo; a chamada
  # interna só vê tudo quando diz `interno: true`. Qualquer outro contexto sem identidade NÃO vê (fail-closed): super
  # admin ou usuário sem AccountUser na conta, token sem dono reconhecido. O mesmo para card, conversa, opções e filtros.
  def ve_no_contexto?(user, account_user, interno: false)
    return true if interno
    return true if user.is_a?(AgentBot)

    ve?(account_user)
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
  def atributos_para(user, account_user, atributos)
    return atributos unless atributos.is_a?(Hash) && com_anuncio?(atributos)
    return atributos if ve_no_contexto?(user, account_user)

    oculta_atributos(atributos)
  end

  # O push_event_data da conversa (notificação): o mesmo, com os additional_attributes como quem lê vê.
  def evento_para(user, account_user, dados)
    return dados unless dados.is_a?(Hash) && dados[:additional_attributes].is_a?(Hash)

    dados.merge(additional_attributes: atributos_para(user, account_user, dados[:additional_attributes].stringify_keys))
  end

  # A conversa tem algum toque de anúncio? Sem ele não há nada a esconder (e o tempo real não consulta quem vê).
  def com_anuncio?(atributos)
    toques_de(atributos).any? { |toque| fonte_de_anuncio(toque) }
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
    toques_de(atributos).select { |toque| fonte_de_anuncio(toque) }.pluck('source_id')
  end

  def toques_de(atributos)
    (Array(atributos['campaign_touches']) + [atributos['campaign']]).select { |toque| toque.is_a?(Hash) }
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
