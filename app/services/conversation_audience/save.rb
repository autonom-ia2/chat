# "Salvar público" of a search by conversation (#2277): the people the person kept become a regular saved audience
# (CampaignImport, flow audience, completed), exactly what the spreadsheet flow leaves behind, so the audience list,
# "Criar campanha" and the send (CampaignJourney::AudienceContacts) treat both the same. The contacts already exist:
# nothing is imported and no contact is written; each row points to its contact with the hashes of its current
# phone and e-mail, the consent proof the send checks again, plus the company and what else the contact has (city,
# country, custom attributes) as columns the message can use (ConversationAudience::Columns) — only when the person
# saving reads contacts (contact_view); otherwise the audience carries name, phone and e-mail only.
#
# Only people of this search whose conversation the person can still open are saved, and never someone left aside
# (ConversationAudience::Reach). The audience itself is written by CampaignJourney::AudienceWriter (#2695).
class ConversationAudience::Save
  Error = Class.new(StandardError)
  MAX_PEOPLE = 20_000

  def initialize(search, user:, name:, person_ids:)
    @search = search
    @account = search.account
    @user = user
    @name = name.to_s.strip.first(255)
    @person_ids = Array(person_ids).first(MAX_PEOPLE).map(&:to_i).uniq
  end

  def perform
    raise Error, 'name_required' if @name.blank?

    people = contacts
    raise Error, 'no_people' if people.empty?

    @columns = ConversationAudience::Columns.new(@account, reads_contacts? ? people : [])
    rows = people.map { |contact| row_for(contact) }

    ActiveRecord::Base.transaction do
      # Two clicks on "Salvar" never make two audiences: the second waits here and finds the search saved.
      @search.lock!
      raise Error, 'already_saved' if @search.status == ConversationAudienceSearch::SAVED
      raise Error, 'not_finished' if @search.running?

      audience = writer.perform(@name, rows)
      @search.update!(status: ConversationAudienceSearch::SAVED, campaign_import: audience)
      audience
    end
  end

  private

  def contacts
    people = @search.people.where(id: @person_ids)
    visible = ConversationAudience::Conversations.visible_ids(@account, @user, people.pluck(:conversation_id))
    contact_ids = people.where(conversation_id: visible.to_a).pluck(:contact_id)
    found = @account.contacts.where(id: contact_ids).order(:id)
    # The company lives in the Enterprise overlay (Enterprise::Concerns::Contact); read it in one query when it is there.
    found = (Contact.reflect_on_association(:company) ? found.includes(:company) : found).to_a
    aside = ConversationAudience::Reach.left_aside(found)
    found.reject { |contact| aside.key?(contact.id) }
  end

  def row_for(contact)
    CampaignJourney::AudienceWriter::Row.new(
      contact_id: contact.id, name: contact.name, phone: ConversationAudience::Reach.phone(contact),
      email: ConversationAudience::Reach.email(contact), company_name: (company_name(contact) if reads_contacts?),
      extra_values: @columns.values_for(contact)
    )
  end

  def writer
    CampaignJourney::AudienceWriter.new(
      @account,
      user: @user,
      source: ConversationAudience::Access::SOURCE,
      options: { 'conversation_audience_search_id' => @search.id },
      columns: @columns
    )
  end

  def reads_contacts?
    return @reads_contacts if defined?(@reads_contacts)

    @reads_contacts = ConversationAudience::Access.reads_contacts?(AccountUser.find_by(account: @account, user: @user))
  end

  # The same reading the message uses for empresa_cliente.nome (TemplateFields::ContactResolver).
  def company_name(contact)
    contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name'].to_s.squish.presence
  end
end
