class EmailCampaigns::Presentation::Errors
  PROTECTION_CODES = {
    'reputation_paused' => 'reputation', 'legacy_pause' => 'reputation', 'reputation_threshold' => 'reputation',
    'provider_blocked' => 'provider', 'provider_manual_block' => 'provider', 'provider_telemetry_unknown' => 'provider',
    'ses_account_paused' => 'provider', 'ses_sending_disabled' => 'provider',
    'hygiene_validation_required' => 'hygiene', 'recipient_import_active' => 'hygiene', 'campaign_not_paused' => 'hygiene',
    'reputation_evaluation_superseded' => 'technical', 'reputation_configuration_invalid' => 'technical'
  }.freeze
  IMPORT_CODES = %w[upload_failed file_expired import_failed unsupported_file_format file_too_large invalid_file empty_file row_limit_exceeded
                    invalid_csv invalid_xlsx].freeze

  def self.protection(value)
    value = value.to_h.with_indifferent_access
    nested = value[:protection].to_h.with_indifferent_access
    cause = PROTECTION_CODES.key?(nested[:code]) ? nested : value
    code = cause[:code]
    if !PROTECTION_CODES.key?(code) && value[:blocked] == true
      return { kind: 'reputation', code: 'reputation_paused', overridable: false, resume_allowed: false }
    end
    return { kind: 'technical', code: 'unknown', overridable: false, resume_allowed: false } unless PROTECTION_CODES.key?(code)

    { kind: PROTECTION_CODES.fetch(code), code: code, overridable: cause[:overridable] == true, resume_allowed: false }
  end

  def self.import_code(value)
    return if value.blank?

    IMPORT_CODES.include?(value) ? value : 'import_failed'
  end

  def self.campaign_code(value)
    return if value.blank?

    PROTECTION_CODES.key?(value) ? value : 'email_campaign.failed'
  end
end
