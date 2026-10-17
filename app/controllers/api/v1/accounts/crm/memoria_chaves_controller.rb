# O catálogo de chaves da memória das IAs (#1601), para o administrador: a IA não cria chave; aqui se diz quais campos
# têm vários itens (cardinalidade N), qual identifica o item (a placa), quais são identidade, quais são obrigatórios no
# pedido e por quantos dias valem. Sem a flag, 404. A tela vem depois do mockup.
class Api::V1::Accounts::Crm::MemoriaChavesController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_memoria
  before_action :ensure_administrator

  def index
    chaves = ::Crm::Memoria::Catalogo.da_conta(Current.account).values.sort_by { |chave| [chave.attribute_model, chave.chave] }
    render json: { payload: chaves.map { |chave| payload(chave) } }
  end

  def update
    chave = ::Crm::MemoriaChave.where(account_id: Current.account.id).find(params[:id])
    return render_unprocessable(chave.errors.full_messages.to_sentence) unless chave.update(atributos)

    render json: { payload: payload(chave) }
  end

  private

  def ensure_memoria
    render json: { error: 'crm.memoria.disabled' }, status: :not_found unless ::Crm::Memoria.ligada?(Current.account)
  end

  def ensure_administrator
    render json: { error: 'crm.memoria.forbidden' }, status: :forbidden unless administrator?
  end

  def atributos
    permitidos = params.permit(:cardinalidade, :item_natural, :identidade, :obrigatoria, :validade_dias)
    permitidos[:cardinalidade] = permitidos[:cardinalidade].to_s == 'N' ? 2 : 1 if permitidos.key?(:cardinalidade)
    permitidos
  end

  def payload(chave)
    chave.slice(:id, :attribute_model, :chave, :rotulo, :nivel, :item_natural, :identidade, :obrigatoria, :validade_dias)
         .merge(cardinalidade: chave.varios? ? 'N' : '1')
  end
end
