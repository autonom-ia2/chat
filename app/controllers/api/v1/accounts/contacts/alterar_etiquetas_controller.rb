# #2461 — pôr e tirar etiquetas do contato uma a uma (AlterarEtiquetasConcern). Quem pode é quem pode mudar as
# etiquetas do contato pela rota de sempre (Contacts::LabelsController: update? do contato).
class Api::V1::Accounts::Contacts::AlterarEtiquetasController < Api::V1::Accounts::Contacts::BaseController
  include AlterarEtiquetasConcern
  before_action -> { authorize @contact, :update? }

  private

  def model
    @contact
  end

  def vista_das_etiquetas
    'api/v1/accounts/contacts/labels/create'
  end
end
