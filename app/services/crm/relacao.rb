# Este contato é (#2084/#2085): interessado (o padrão), parceiro do mercado ou não é negócio. Uma regra só, atrás da
# flag `contato_relacao` da conta; desligada, todo contato é do funil, como antes.
#
#   Crm::Relacao.ligada?(account)            -> a flag está ligada?
#   Crm::Relacao.fora_do_funil?(contact)     -> não vira card sozinho (quem cria card automático pergunta aqui)
#   Crm::Relacao.cards_do_funil(account)     -> os cards que contam nos Números (sem os de contato fora do funil)
#
# Card criado à mão por uma pessoa continua valendo: a trava é só dos caminhos automáticos.
module Crm::Relacao
  module_function

  FLAG = 'contato_relacao'.freeze

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def fora_do_funil?(contact)
    contact.present? && !contact.relacao_interessado? && ligada?(contact.account)
  end

  # NOT EXISTS, e não NOT IN: card sem contato continua contando.
  def cards_do_funil(account)
    cards = account.crm_cards
    return cards unless ligada?(account)

    cards.where(<<~SQL.squish, Contact.defined_enums.fetch('relacao').fetch('interessado'))
      NOT EXISTS (SELECT 1 FROM contacts fora WHERE fora.id = crm_cards.contact_id AND fora.relacao <> ?)
    SQL
  end
end
