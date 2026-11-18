# "Enviar" a proposta de renovação pelo card (E8, #2901, modo `quem_envia = pessoa`): nada sai antes deste clique. Pede
# poder editar a pessoa do seguro (`contact_manage`, a régua da carteira) e enxergar o card de renovação no quadro
# (Carteira::CardsVisiveis): quem não vê o card não manda a proposta dele. O envio é o de Carteira::Cotacao::Proposta,
# com quem clicou; o que impede responde 422 com o código (`cotacao_desligada`, `proposta_ja_enviada`, `sem_proposta`
# ou o motivo do envio que não saiu, como `sem_modelo` e `contato_recusou`). Saiu: responde o seguro, já com a cotação.
class Api::V1::Accounts::Relacionamentos::Seguros::PropostasController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :achar_seguro
  before_action :poder_editar
  before_action :ver_o_card

  # POST seguros/:id/enviar_proposta
  def create
    corpo
    config = ::Carteira::RenovacaoConfig.find_by(account_id: Current.account.id)
    ::Carteira::Cotacao::Proposta.new(@seguro, config, user: Current.user).enviar
    responder_seguro(@seguro.reload)
  end

  private

  def ver_o_card
    card_id = @seguro.crm_card_id
    raise Pundit::NotAuthorizedError unless card_id && ::Carteira::CardsVisiveis.new(pundit_user).call.exists?(id: card_id)
  end
end
