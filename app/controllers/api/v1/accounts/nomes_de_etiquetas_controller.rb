# Nome livre das etiquetas (#1823, F1a): o que aparece no painel no lugar do `title` técnico.
#
#   GET    /api/v1/accounts/:account_id/nomes_de_etiquetas            => { payload: [{ label_id, nome }] }
#   PUT    /api/v1/accounts/:account_id/nomes_de_etiquetas/:label_id  { nome } => { payload: { label_id, nome } }
#   DELETE /api/v1/accounts/:account_id/nomes_de_etiquetas/:label_id  => 204
#
# Ler: quem lista as etiquetas (LabelPolicy#index?). Gravar e apagar: quem gerencia etiquetas (LabelPolicy#update?,
# `label_manage` com as funções personalizadas do EE). Sem a flag `etiquetas_do_whatsapp`, 404 para todos.
class Api::V1::Accounts::NomesDeEtiquetasController < Api::V1::Accounts::BaseController
  before_action :exigir_flag
  before_action :buscar_etiqueta, only: [:update, :destroy]
  before_action :autorizar

  def index
    nomes = Etiquetas::Nome.where(account: Current.account).pluck(:label_id, :nome)
    render json: { payload: nomes.map { |label_id, nome| { label_id: label_id, nome: nome } } }
  end

  def update
    registro = gravar_nome(params[:nome].to_s.strip)
    render json: { payload: { label_id: registro.label_id, nome: registro.nome } }
  end

  def destroy
    Etiquetas::Nome.where(label: @label).delete_all
    head :no_content
  end

  private

  def exigir_flag
    head :not_found unless Current.account.feature_enabled?('etiquetas_do_whatsapp')
  end

  # Dois PUTs ao mesmo tempo na primeira gravação: o segundo bate no índice único e grava por cima do primeiro.
  def gravar_nome(nome, tentar_de_novo: true)
    registro = Etiquetas::Nome.find_or_initialize_by(label: @label)
    registro.update!(account: Current.account, nome: nome)
    registro
  rescue ActiveRecord::RecordNotUnique
    raise unless tentar_de_novo

    gravar_nome(nome, tentar_de_novo: false)
  end

  def buscar_etiqueta
    @label = Current.account.labels.find(params[:label_id])
  end

  def autorizar
    authorize(@label || Label, action_name == 'index' ? :index? : :update?)
  end
end
