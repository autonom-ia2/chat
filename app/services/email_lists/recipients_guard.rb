# A campanha de e-mail com lista (G52, #2760) recebe os destinatários só da lista: subir planilha nela é recusado, para
# a lista nunca se misturar com outra fonte. Prependido em Api::V1::Accounts::EmailCampaigns::RecipientsController por
# config/initializers/email_lists.rb (@campaign vem do before_action dele).
module EmailLists::RecipientsGuard
  def create
    return render_email_list_linked if @campaign.email_list_id.present?

    super
  end

  def retry_import
    return render_email_list_linked if @campaign.email_list_id.present?

    super
  end

  private

  def render_email_list_linked
    render json: { error: 'email_campaign.email_list_linked' }, status: :unprocessable_entity
  end
end
