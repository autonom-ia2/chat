# Apagar a etiqueta de uma lista de e-mail (G52, #2760) apaga a lista junto (EmailLists::LabelList). Por isso a tela de
# etiquetas segue a mesma regra e a mesma trava do apagar a lista (Api::V1::Accounts::EmailCampaigns::ListsController):
# recusa enquanto uma campanha agendada, em envio ou pausada usa a lista. Prependido em
# Api::V1::Accounts::LabelsController por config/initializers/email_lists.rb (@label vem do before_action dele).
module EmailLists::LabelDestroyGuard
  def destroy
    lista = @label.email_list
    return super if lista.nil?
    return if lista.sem_campanha_em_uso { super }

    render json: { error: 'email_list.in_use', message: I18n.t('email_lists.label_in_use') }, status: :unprocessable_entity
  end
end
