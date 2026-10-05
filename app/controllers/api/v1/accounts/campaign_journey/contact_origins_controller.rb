# "Origem e campanhas" of the contact panel (#1002, PRD D20, §6.11 and P1): every origin and
# campaign mark of the contact's conversations the agent can see, in order (first touch first,
# like the CRM card), plus the audiences (Públicos) the contact is in. Read-only.
class Api::V1::Accounts::CampaignJourney::ContactOriginsController < Api::V1::Accounts::BaseController
  MAX_CONVERSATIONS = 50
  MARK_KEYS = %w[source source_id source_type headline source_url touched_at].freeze

  def show
    contact = Current.account.contacts.find(params[:id])
    authorize contact, :show?

    render json: { payload: { marks: marks_for(contact), audiences: audiences_for(contact) } }
  end

  private

  def marks_for(contact)
    conversations = visible_conversations.where(contact_id: contact.id).order(:created_at).limit(MAX_CONVERSATIONS)
    marks = conversations.flat_map { |conversation| conversation_marks(conversation) }
    marks.sort_by { |mark| mark['touched_at'].to_s }
  end

  # Legacy single-touch conversations come back as one touch (Ctwa::CampaignBuilder.existing_touches).
  def conversation_marks(conversation)
    Ctwa::CampaignBuilder.existing_touches(conversation).map do |touch|
      touch.slice(*MARK_KEYS).merge('conversation_display_id' => conversation.display_id)
    end
  end

  # Same visibility the conversation list uses (Conversations::PermissionFilterService).
  def visible_conversations
    Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform.reorder(nil)
  end

  # Old campaign bases have no name: they show the name of their campaign.
  def audiences_for(contact)
    imports = Current.account.campaign_imports
                     .where(id: CampaignImportRow.status_imported.where(contact_id: contact.id).select(:campaign_import_id))
                     .order(:created_at)
    imports.map { |import| { id: import.id, name: import.name.presence || import.campaign_name } }
  end
end
