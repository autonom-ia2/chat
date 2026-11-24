# #3101 (D1): o público da segunda mensagem — uma cópia das linhas do público da primeira, só das pessoas que vão
# receber de novo. As linhas são copiadas como estão (nome, os hashes do telefone e do e-mail que provam o
# consentimento, empresa e colunas extras), então as colunas que a mensagem usa e a conferência do envio continuam as
# mesmas. Gravado como qualquer público (CampaignJourney::AudienceWriter), com a origem 'segunda_mensagem'.
class CampaignJourney::Reenvio::Publico < CampaignJourney::AudienceWriter
  SOURCE = 'segunda_mensagem'.freeze
  COPIADAS = %w[contact_id raw_name normalized_name normalized_phone_hash raw_phone_masked normalized_email_hash email_masked
                company_name extra_values].freeze

  # `row`: uma CampaignImportRow do público da primeira.
  def self.row_attributes(row)
    row.attributes.slice(*COPIADAS).symbolize_keys.merge(extra_values: row.extra_values || {})
  end

  # O público novo, ou nil quando nenhuma linha do público da primeira é dessas pessoas.
  def self.copiar(original, contact_ids, nome:)
    linhas = CampaignImportRow.where(campaign_import_id: original.id, contact_id: contact_ids).where.not(contact_id: nil).order(:row_number).to_a
    return if linhas.empty?

    colunas = Columns.new(original.extra_columns || [], original.schema_resolution.to_h[CampaignImports::ColumnTypes::RESOLUTION_KEY] || {})
    new(original.account, user: original.user, source: SOURCE, columns: colunas).perform(nome, linhas)
  end
end
