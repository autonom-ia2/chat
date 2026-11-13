# Como terminou a renovação de um seguro, pela gaveta (E5, #2898): "Renovou", "Não renovou" (com o motivo) e "Desfazer".
# Cada uma fecha ou reabre o card de renovação do seguro e devolve o seguro como ficou. Pede poder editar a pessoa do
# seguro e poder fechar o card dele no quadro (Crm::CardPolicy#close?): quem não mexe naquele funil recebe 401.
class Api::V1::Accounts::Relacionamentos::Seguros::DesfechosController < Api::V1::Accounts::Relacionamentos::CarteiraController
  before_action :achar_seguro
  before_action :poder_editar
  before_action :poder_fechar_o_card

  def renovou
    corpo
    responder_seguro(fechar.renovou)
  end

  def nao_renovou
    dito = corpo(:motivo, :texto)
    responder_seguro(fechar.nao_renovou(motivo: dito['motivo'], texto: dito['texto']))
  end

  def desfazer
    corpo
    responder_seguro(fechar.desfazer)
  end

  private

  # Sem card não há o que conferir: a recusa `sem_renovacao` é do serviço.
  def poder_fechar_o_card
    authorize @seguro.crm_card, :close? if @seguro.crm_card
  end

  def fechar
    ::Carteira::Renovacao::Fechar.new(@seguro, user: Current.user)
  end
end
