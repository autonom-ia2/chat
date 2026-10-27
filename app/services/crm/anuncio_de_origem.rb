# Quem vê qual anúncio trouxe o cliente, no card do CRM (#2271; decisão do Rodrigo, 27/10): o administrador e a função
# com `meta_ads_view` (ou `meta_ads_manage`, que implica a view; Enterprise::AccountUser#permission_granted?). Os outros
# veem só que o cliente veio de anúncio, e por onde (Meta, Google, TikTok) e quando, como já acontece com o gasto.
#
# O toque de anúncio sai sem o que identifica o anúncio: título, nomes de campanha/grupo/anúncio, prévia, miniatura,
# endereço, UTMs e o id do anúncio. É de anúncio pelo `source` gravado ou pela regra de "pago" do próprio
# Ctwa::CampaignBuilder.source_for, refeita sobre o toque (pega o toque antigo). Fica a origem (`source`),
# `source_type`, `touched_at` e `conversation_id`, com `ad_hidden: true`. Toque que não é anúncio (publicação, link do
# site, divulgação por WhatsApp, e-mail, SMS ou chat do site) não muda.
#
#   Crm::AnuncioDeOrigem.ve?(account_user)          -> true | false
#   Crm::AnuncioDeOrigem.para_quem_nao_ve(toque, item) -> o item do card, sem o anúncio quando o toque é de anúncio
module Crm::AnuncioDeOrigem
  CHAVE = 'meta_ads_view'.freeze
  FONTES_DE_ANUNCIO = %w[meta_ctwa meta_paid google_ads tiktok_ads].freeze
  CAMPOS_QUE_FICAM = %i[source source_type touched_at conversation_id].freeze

  module_function

  def ve?(account_user)
    account_user.present? && account_user.permission_granted?(CHAVE)
  end

  # toque: o toque gravado na conversa (chaves em texto); item: o mesmo toque já no formato do card.
  def para_quem_nao_ve(toque, item)
    fonte = fonte_de_anuncio(toque)
    return item if fonte.blank?

    item.to_h { |campo, valor| [campo, CAMPOS_QUE_FICAM.include?(campo) ? valor : nil] }
        .merge(source: fonte, ad_hidden: true)
  end

  # A origem de anúncio do toque, ou nil. Vale o `source` gravado e também a regra de hoje do próprio código para
  # "pago" (Ctwa::CampaignBuilder.source_for: ctwa_clid ou source_type 'ad', gclid, ttclid, fbclid ou as UTMs da Meta
  # pagas), refeita sobre o toque: o toque gravado antes da regra mudar (UTMs do #1011, `source` que não existia)
  # ficou com outra origem, mas carrega os mesmos sinais.
  def fonte_de_anuncio(toque)
    gravada = toque['source'].to_s
    return gravada if FONTES_DE_ANUNCIO.include?(gravada)

    pela_regra = Ctwa::CampaignBuilder.source_for(toque.symbolize_keys)
    pela_regra if FONTES_DE_ANUNCIO.include?(pela_regra)
  end
end
