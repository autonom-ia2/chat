# Extra columns of an audience as message tokens (#999, PRD §6.3). Each spreadsheet header kept in
# campaign_imports.extra_columns gets the normalized key the spreadsheet import uses
# (CampaignImports::HeaderMapper.normalize_key: "Data de Vencimento" → "data_de_vencimento"; a
# repeated key gets "_2"). The value of a person is campaign_import_rows.extra_values[header] of
# the contact's first imported row.
module CampaignJourney::AudienceColumns
  # WhatsApp API token prefix: {{publico.vencimento}}.
  PREFIX = 'publico.'.freeze

  module_function

  # { 'vencimento' => 'Vencimento', 'data_de_vencimento' => 'Data de Vencimento' }
  def key_map(campaign_import)
    Array(campaign_import&.extra_columns).each_with_object({}) do |header, map|
      key = CampaignImports::HeaderMapper.normalize_key(header)
      next if key.empty?

      key = "#{key}_2" while map.key?(key)
      map[key] = header.to_s
    end
  end

  # { 'vencimento' => '10/2026' } for one row's extra_values (values squished, blanks dropped).
  def values_for(campaign_import, extra_values)
    values = extra_values.to_h
    key_map(campaign_import).transform_values { |header| values[header].to_s.squish }.compact_blank
  end

  # 'publico.vencimento' → 'vencimento'; nil for other tokens.
  def column_key(token)
    token.to_s.start_with?(PREFIX) ? token.to_s.delete_prefix(PREFIX) : nil
  end

  def token(key)
    "#{PREFIX}#{key}"
  end

  # extra_values of the contact's first imported row in the audience.
  def row_values(campaign_import, contact_id)
    return {} if campaign_import.nil?

    row = campaign_import.campaign_import_rows.status_imported.where(contact_id: contact_id).order(:row_number).first
    values_for(campaign_import, row&.extra_values)
  end
end
