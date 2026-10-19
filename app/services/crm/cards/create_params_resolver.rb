class Crm::Cards::CreateParamsResolver
  LINK_ATTRIBUTES = %i[contact_id conversation_id inbox_id owner_id team_id].freeze

  def initialize(account:, user_context:, params:, conversation: nil)
    @account = account
    @user_context = user_context
    @account_user = user_context[:account_user]
    @attributes = params.dup
    @conversation = conversation
  end

  def perform
    return @attributes.except(*LINK_ATTRIBUTES) if @conversation.present?

    resolve_account_record(:pipeline_id, @account.crm_pipelines)
    resolve_account_record(:stage_id, @account.crm_pipeline_stages)
    resolve_contact_id
    resolve_inbox_id
    resolve_account_record(:owner_id, @account.users)
    resolve_account_record(:team_id, @account.teams)
    @attributes
  end

  private

  def resolve_account_record(attribute, relation)
    return if @attributes[attribute].blank?

    @attributes[attribute] = relation.find(@attributes[attribute]).id
  end

  # O card devolve o contato vinculado (#1849): só vincula quem vê esse contato.
  def resolve_contact_id
    return if @attributes[:contact_id].blank?

    contact = @account.contacts.find(@attributes[:contact_id])
    Pundit.authorize(@user_context, contact, :attach?)
    @attributes[:contact_id] = contact.id
  end

  def resolve_inbox_id
    return if @attributes[:inbox_id].blank?

    inbox = @account.inboxes.find(@attributes[:inbox_id])
    Pundit.authorize(@user_context, inbox, :show?) unless administrator?
    @attributes[:inbox_id] = inbox.id
  end

  def administrator?
    @account_user&.administrator?
  end
end
