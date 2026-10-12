# Corpo do 422 de ActiveRecord::RecordInvalid para FollowUpsController (achado da revisão em #1349):
# soma um `code` estável quando a validação é o fallback de template, para a tela não depender do
# texto da mensagem (que é do Rails e muda com o locale/versão).
class Crm::FollowUps::RecordInvalidResponse
  TEMPLATE_FALLBACK_CODE = 'template_fallback_required'.freeze

  def self.render(exception)
    {
      message: exception.record.errors.full_messages.join(', '),
      attributes: exception.record.errors.attribute_names,
      code: (TEMPLATE_FALLBACK_CODE if template_fallback?(exception.record))
    }.compact
  end

  def self.template_fallback?(record)
    record.errors.details[:metadata].to_a.any? { |detail| detail[:error] == :template_fallback_required }
  end
end
