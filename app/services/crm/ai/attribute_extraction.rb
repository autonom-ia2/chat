# Extração de campos personalizados na avaliação do card (contato, conversa e o próprio card, #1146): se está ligada no
# funil, o schema que vai ao classificador e a gravação do que ele extraiu. Falha aqui nunca quebra a avaliação.
class Crm::Ai::AttributeExtraction
  EMPTY_SCHEMA = { contact: [], conversation: [], card: [] }.freeze

  def initialize(card:)
    @card = card
  end

  def enabled?
    return @enabled if defined?(@enabled)

    @enabled = Crm::Ai::Config.attribute_extraction_enabled? &&
               Crm::Ai::Config.pipeline_attribute_extraction_enabled?(@card.pipeline)
  end

  def schema
    return EMPTY_SCHEMA unless enabled?

    @schema ||= Crm::Ai::AttributeSchemaBuilder.new(account: @card.account, prefix: prefix).perform
  end

  def apply(extracted_attributes)
    return unless enabled?

    Crm::Ai::AttributeExtractorApplier.new(
      card: @card, extracted_attributes: extracted_attributes, prefix: prefix,
      min_confidence: Crm::Ai::Config.attribute_extraction_min_confidence(@card.pipeline)
    ).perform
  rescue StandardError => e
    Rails.logger.error("[CRM AI attribute extraction] #{e.class}: #{e.message}")
  end

  private

  def prefix
    Crm::Ai::Config.attribute_extraction_prefix(@card.pipeline)
  end
end
