# "Salvar público" of a search by conversation (#2277): the people the person kept become a regular saved audience
# (CampaignImport, flow audience, completed), exactly what the spreadsheet flow leaves behind, so the audience list,
# "Criar campanha" and the send (CampaignJourney::AudienceContacts) treat both the same. The contacts already exist:
# nothing is imported and no contact is written; each row points to its contact with the hashes of its current
# phone and e-mail, the consent proof the send checks again, plus the company and what else the contact has (city,
# country, custom attributes) as columns the message can use (ConversationAudience::Columns) — only when the person
# saving reads contacts (contact_view); otherwise the audience carries name, phone and e-mail only.
#
# Only people of this search whose conversation the person can still open are saved, and never someone left aside
# (ConversationAudience::Reach).
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

      audience = create_audience(rows)
      insert_rows(audience, rows)
      audience.update!(channels: CampaignJourney::AudienceContacts.recounted_channels(audience))
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
    phone = ConversationAudience::Reach.phone(contact)
    email = ConversationAudience::Reach.email(contact)
    {
      contact_id: contact.id, raw_name: contact.name, normalized_name: contact.name.to_s.squish,
      normalized_phone_hash: phone&.hash, raw_phone_masked: phone&.masked,
      normalized_email_hash: email && Digest::SHA256.hexdigest(email.email), email_masked: email&.masked,
      company_name: (company_name(contact) if reads_contacts?), extra_values: @columns.values_for(contact)
    }
  end

  def reads_contacts?
    return @reads_contacts if defined?(@reads_contacts)

    @reads_contacts = ConversationAudience::Access.reads_contacts?(AccountUser.find_by(account: @account, user: @user))
  end

  # The same reading the message uses for empresa_cliente.nome (TemplateFields::ContactResolver).
  def company_name(contact)
    contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name'].to_s.squish.presence
  end

  def create_audience(rows)
    now = Time.current
    @account.campaign_imports.create!(
      user: @user, status: :completed, mode: 'single_label', name: @name, campaign_name: @name, batch_count: 1,
      options: { 'default_country' => 'BR', 'flow' => CampaignImport::AUDIENCE_FLOW, 'create_companies' => false,
                 'source' => ConversationAudience::Access::SOURCE, 'conversation_audience_search_id' => @search.id },
      total_rows: rows.size, valid_rows: rows.size, imported_contacts_count: rows.size, existing_contacts_count: rows.size,
      validation_summary: { 'errors' => {}, 'warnings' => [] }, channels: initial_channels(rows),
      extra_columns: @columns.headers, schema_resolution: { CampaignImports::ColumnTypes::RESOLUTION_KEY => @columns.types },
      validated_at: now, confirmed_at: now, import_started_at: now, import_finished_at: now
    )
  end

  def insert_rows(audience, rows)
    now = Time.current
    # Same rows the spreadsheet importer leaves, built from contacts of this account; one insert for the whole list.
    CampaignImportRow.insert_all!(rows.each_with_index.map do |row, index| # rubocop:disable Rails/SkipsModelValidations
      row.merge(campaign_import_id: audience.id, row_number: index + 1, batch_index: 0,
                status: CampaignImportRow.statuses[:imported], was_existing_contact: true,
                labels_applied: [], error_messages: [], created_at: now, updated_at: now)
    end)
  end

  # Same shape the spreadsheet validator writes; the recount after the rows keeps it true to the contacts.
  def initial_channels(rows)
    phones = rows.count { |row| row[:normalized_phone_hash] }
    emails = rows.count { |row| row[:normalized_email_hash] }
    {
      'whatsapp' => { 'enabled' => phones.positive?, 'count' => phones },
      'email' => { 'enabled' => emails.positive?, 'count' => emails },
      'sms' => { 'enabled' => phones.positive? && CampaignJourney::AudienceContacts.sms_inbox_connected?(@account), 'count' => phones }
    }
  end
end
