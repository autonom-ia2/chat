# LGPD (#2096): excluir o contato com `delete_crm_cards=true` apaga de vez os cards dele junto. Excluir de vez é só de
# administrador, também no EE (quem tem contact_delete exclui o contato, mas não os cards junto). Sem o parâmetro, os
# cards ficam sem contato, como sempre.
module Crm::ContactCardsDeletion
  private

  def delete_crm_cards?
    ActiveModel::Type::Boolean.new.cast(params[:delete_crm_cards]) || false
  end

  def destroy_with_crm_cards
    return render json: { error: 'crm.permanent_delete.admin_only' }, status: :forbidden unless Current.account_user&.administrator?

    ::Crm::ExclusaoDefinitiva.contato!(contact: @contact, user: Current.user)
    head :ok
  rescue ::Crm::Cards::Excluidor::ReuniaoNaoCancelada => e
    render json: { error: 'crm.permanent_delete.meeting_cancel_failed', meeting_id: e.meeting_id }, status: :unprocessable_entity
  end
end
