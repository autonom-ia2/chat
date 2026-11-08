# Writes a saved audience (Público) from people already resolved to contacts of the account (#2695): a regular
# CampaignImport of the audience flow, completed, with one imported row per person, exactly what the spreadsheet flow
# leaves behind, so the audience list, "Criar campanha" and the send (CampaignJourney::AudienceContacts) treat it the
# same. Nothing is imported and no contact is written; each row points to its contact with the hashes of its phone and
# e-mail, the consent proof the send checks again.
#
# The caller decides who enters, which extra columns the message can use, and where the audience came from
# (options['source']). First caller: ConversationAudience::Save (#2277, source 'conversations').
class CampaignJourney::AudienceWriter
  # One person of the audience. phone: a CampaignImports::PhoneNormalizer result (hash, masked) or nil; email: an
  # EmailCampaigns::EmailNormalizer result (email, masked) or nil; extra_values: { header => value } of extra_columns.
  Row = Struct.new(:contact_id, :name, :phone, :email, :company_name, :extra_values, keyword_init: true)
  # The extra columns the rows carry: headers in order (campaign_imports.extra_columns) and { header => type }
  # (CampaignImports::ColumnTypes). ConversationAudience::Columns answers the same two.
  Columns = Struct.new(:headers, :types)
  NO_COLUMNS = Columns.new([].freeze, {}.freeze).freeze
  Error = Class.new(StandardError)
  MAX_NAME = 255
  # Options every audience written here carries; a caller never sets them through options:.
  RESERVED_OPTIONS = %w[default_country flow create_companies source].freeze

  # The columns of one campaign_import_rows row of a person (name, phone and e-mail hashes and masks, company, extra
  # values), the same perform inserts. Also for a caller that adds one person to an audience that already exists.
  def self.row_attributes(row)
    {
      contact_id: row.contact_id, raw_name: row.name, normalized_name: row.name.to_s.squish,
      normalized_phone_hash: row.phone&.hash, raw_phone_masked: row.phone&.masked,
      normalized_email_hash: row.email && Digest::SHA256.hexdigest(row.email.email), email_masked: row.email&.masked,
      company_name: row.company_name, extra_values: row.extra_values || {}
    }
  end

  # Saves the channels of an audience recounted from its rows' contacts (CampaignJourney::AudienceContacts), after its
  # rows changed. Returns the audience.
  def self.recount_channels(audience)
    audience.update!(channels: CampaignJourney::AudienceContacts.recounted_channels(audience))
    audience
  end

  def initialize(account, user:, source:, options: {}, columns: NO_COLUMNS)
    reserved = options.keys.map(&:to_s) & RESERVED_OPTIONS
    raise ArgumentError, "reserved option: #{reserved.join(', ')}" if reserved.any?

    @account = account
    @user = user
    @source = source
    @options = options
    @columns = columns
  end

  # The audience named name (stripped, up to 255 characters), saved with its rows and its channels recounted from the
  # contacts. A person repeated keeps only their first row, in the order given. Refused before anything is written:
  # a blank name (Error 'name_required'), an empty list (Error 'no_rows'), and a row whose contact is not of this
  # account (Error 'foreign_contact'). The transaction joins the caller's one when there is one (no requires_new),
  # so a failure of the caller after this also undoes the audience.
  def perform(name, rows)
    name = name.to_s.strip.first(MAX_NAME)
    raise Error, 'name_required' if name.blank?
    raise Error, 'no_rows' if rows.empty?

    rows = rows.uniq(&:contact_id)
    raise Error, 'foreign_contact' unless own_contacts?(rows)

    records = rows.map { |row| self.class.row_attributes(row) }

    ActiveRecord::Base.transaction do
      audience = create_audience(name, records)
      insert_rows(audience, records)
      self.class.recount_channels(audience)
    end
  end

  private

  # One query: every contact of the rows (already unique) belongs to this account.
  def own_contacts?(rows)
    @account.contacts.where(id: rows.map(&:contact_id)).count == rows.size
  end

  def create_audience(name, records)
    now = Time.current
    @account.campaign_imports.create!(
      user: @user, status: :completed, mode: 'single_label', name: name, campaign_name: name, batch_count: 1,
      options: { 'default_country' => 'BR', 'flow' => CampaignImport::AUDIENCE_FLOW, 'create_companies' => false,
                 'source' => @source }.merge(@options),
      total_rows: records.size, valid_rows: records.size, imported_contacts_count: records.size,
      existing_contacts_count: records.size, validation_summary: { 'errors' => {}, 'warnings' => [] },
      channels: initial_channels(records), extra_columns: @columns.headers,
      schema_resolution: { CampaignImports::ColumnTypes::RESOLUTION_KEY => @columns.types },
      validated_at: now, confirmed_at: now, import_started_at: now, import_finished_at: now
    )
  end

  def insert_rows(audience, records)
    now = Time.current
    # Same rows the spreadsheet importer leaves, built from contacts of this account; one insert for the whole list.
    CampaignImportRow.insert_all!(records.each_with_index.map do |record, index| # rubocop:disable Rails/SkipsModelValidations
      record.merge(campaign_import_id: audience.id, row_number: index + 1, batch_index: 0,
                   status: CampaignImportRow.statuses[:imported], was_existing_contact: true,
                   labels_applied: [], error_messages: [], created_at: now, updated_at: now)
    end)
  end

  # Same shape the spreadsheet validator writes; the recount after the rows keeps it true to the contacts.
  def initial_channels(records)
    phones = records.count { |record| record[:normalized_phone_hash] }
    emails = records.count { |record| record[:normalized_email_hash] }
    {
      'whatsapp' => { 'enabled' => phones.positive?, 'count' => phones },
      'email' => { 'enabled' => emails.positive?, 'count' => emails },
      'sms' => { 'enabled' => phones.positive? && CampaignJourney::AudienceContacts.sms_inbox_connected?(@account), 'count' => phones }
    }
  end
end
