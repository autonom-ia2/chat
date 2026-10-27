# Quem vê qual anúncio trouxe o cliente, no card do CRM (#2271; decisão do Rodrigo, 27/10): o administrador e a função
# com `meta_ads_view` (ou `meta_ads_manage`, que implica a view; Enterprise::AccountUser#permission_granted?). Os outros
# veem só que o cliente veio de anúncio, e por onde (Meta, Google, TikTok) e quando, como já acontece com o gasto.
#
# O toque de anúncio sai sem o que identifica o anúncio: título, nomes de campanha/grupo/anúncio, prévia, miniatura,
# endereço, UTMs e o id do anúncio. Fica a origem (`source`, resolvida também no toque antigo sem o campo),
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
    fonte = fonte_do(toque)
    return item unless FONTES_DE_ANUNCIO.include?(fonte)

    item.to_h { |campo, valor| [campo, CAMPOS_QUE_FICAM.include?(campo) ? valor : nil] }
        .merge(source: fonte, ad_hidden: true)
  end

  # O toque sem `source`, gravado antes do campo existir, tem a origem resolvida pela regra do próprio toque, como em
  # Crm::Reports::OriginMetrics e Crm::Numeros::Origens::Classificador.
  def fonte_do(toque)
    toque['source'].to_s.presence || Ctwa::CampaignBuilder.source_for(toque.symbolize_keys)
  end
end
