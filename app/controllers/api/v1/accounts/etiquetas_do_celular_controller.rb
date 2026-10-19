# Etiquetas do WhatsApp do celular (#1823, F1b): quais etiquetas daqui correspondem a uma etiqueta do app WhatsApp
# Business de uma caixa, com o nome que ela tem no celular. Alimenta o selo do WhatsApp no chip e o "No celular: …".
#
#   GET /api/v1/accounts/:account_id/etiquetas_do_celular
#     => { payload: [{ label_id, inbox_id, caixa, nome_no_celular, color_index, criada_pelo_celular }] }
#
# Só leitura (quem grava é o Etiquetas::AplicarEventoDoCelular). Ler: quem lista as etiquetas (LabelPolicy#index?).
# Sem a flag `etiquetas_do_celular`, 404 para todos.
class Api::V1::Accounts::EtiquetasDoCelularController < Api::V1::Accounts::BaseController
  before_action :exigir_flag

  def index
    authorize(Label, :index?)
    registros = Etiquetas::DoCelular.where(account: Current.account).includes(:inbox).order(:id)
    render json: { payload: registros.map { |registro| item(registro) } }
  end

  private

  def exigir_flag
    head :not_found unless Current.account.feature_enabled?('etiquetas_do_celular')
  end

  def item(registro)
    {
      label_id: registro.label_id,
      inbox_id: registro.inbox_id,
      caixa: registro.inbox.name,
      nome_no_celular: registro.nome,
      color_index: registro.color_index,
      criada_pelo_celular: registro.criada_pelo_celular
    }
  end
end
