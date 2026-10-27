# "Salvar público" of a search by conversation (#2277): the people the person kept become a regular saved audience
# (CampaignImport, flow audience, completed), exactly what the spreadsheet flow leaves behind, so the audience list,
# "Criar campanha" and the send (CampaignJourney::AudienceContacts) treat both the same. The contacts already exist:
# nothing is imported and no contact is written; each row points to its contact with the hashes of its current
# phone and e-mail, the consent proof the send checks again.
#
# Only people of this search are saved, and never someone left aside (ConversationAudience::Reach).
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

    rows = contacts.filter_map { |contact| row_for(contact) }
    raise Error, 'no_people' if rows.empty?

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
    contact_ids = @search.people.where(id: @person_ids).pluck(:contact_id)
    found = @account.contacts.where(id: contact_ids).order(:id).to_a
    aside = ConversationAudience::Reach.left_aside(found)
    found.reject { |contact| aside.key?(contact.id) }
  end

  def row_for(contact)
    phone = ConversationAudience::Reach.phone(contact)
    email = normalized_email(contact)
    {
      contact_id: contact.id, raw_name: contact.name, normalized_name: contact.name.to_s.squish,
      normalized_phone_hash: phone&.hash, raw_phone_masked: phone&.masked,
      normalized_email_hash: email && Digest::SHA256.hexdigest(email.email), email_masked: email&.masked
    }
  end

  def normalized_email(contact)
    return if contact.email.blank?

    EmailCampaigns::EmailNormalizer.normalize!(contact.email)
  rescue EmailCampaigns::EmailNormalizer::Error
    nil
  end

  def create_audience(rows)
    now = Time.current
    @account.campaign_imports.create!(
      user: @user, status: :completed, mode: 'single_label', name: @name, campaign_name: @name, batch_count: 1,
      options: { 'default_country' => 'BR', 'flow' => CampaignImport::AUDIENCE_FLOW, 'create_companies' => false,
                 'source' => 'conversations', 'conversation_audience_search_id' => @search.id },
      total_rows: rows.size, valid_rows: rows.size, imported_contacts_count: rows.size, existing_contacts_count: rows.size,
      validation_summary: { 'errors' => {}, 'warnings' => [] }, channels: initial_channels(rows),
      validated_at: now, confirmed_at: now, import_started_at: now, import_finished_at: now
    )
  end

  def insert_rows(audience, rows)
    now = Time.current
    # Same rows the spreadsheet importer leaves, built from contacts of this account; one insert for the whole list.
    CampaignImportRow.insert_all!(rows.each_with_index.map do |row, index| # rubocop:disable Rails/SkipsModelValidations
      row.merge(campaign_import_id: audience.id, row_number: index + 1, batch_index: 0,
                status: CampaignImportRow.statuses[:imported], was_existing_contact: true,
                labels_applied: [], error_messages: [], extra_values: {}, created_at: now, updated_at: now)
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
