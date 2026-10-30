# Este contato é (#2084/#2085): interessado (o padrão), parceiro do mercado ou não é negócio. Uma regra só, atrás da
# flag `contato_relacao` da conta; desligada, todo contato é do funil, como antes.
#
#   Crm::Relacao.ligada?(account)            -> a flag está ligada?
#   Crm::Relacao.fora_do_funil?(contact)     -> não vira card sozinho (quem cria card automático pergunta aqui)
#   Crm::Relacao.cards_do_funil(account)     -> os cards que contam nos Números (sem os de contato fora do funil)
#   Crm::Relacao.condicao_sql(account)       -> a mesma regra em SQL, para consulta escrita à mão (nil com a flag
#                                               desligada); vai somada ao escopo de quem vê, nunca no lugar dele
#
# Card criado à mão por uma pessoa continua valendo: a trava é só dos caminhos automáticos.
module Crm::Relacao
  module_function

  FLAG = 'contato_relacao'.freeze

  # NOT EXISTS, e não NOT IN: card sem contato continua contando. A busca vai pela chave do contato; a conta no
  # filtro não deixa contato de outra conta tirar card desta.
  CONDICAO_SQL = <<~SQL.squish.freeze
    NOT EXISTS (
      SELECT 1 FROM contacts fora
      WHERE fora.account_id = crm_cards.account_id AND fora.id = crm_cards.contact_id AND fora.relacao <> %<interessado>d
    )
  SQL

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def fora_do_funil?(contact)
    contact.present? && !contact.relacao_interessado? && ligada?(contact.account)
  end

  def cards_do_funil(account)
    condicao = condicao_sql(account)
    condicao ? account.crm_cards.where(condicao) : account.crm_cards
  end

  def condicao_sql(account)
    return unless ligada?(account)

    format(CONDICAO_SQL, interessado: Contact.defined_enums.fetch('relacao').fetch('interessado'))
  end
end
