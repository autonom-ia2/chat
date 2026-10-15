# Corpo do 422 de ActiveRecord::RecordInvalid para FollowUpsController (achado da revisão em #1349):
# soma um `code` estável quando a validação é o fallback de template ou o horário que já passou (#1590), para a tela
# não depender do texto da mensagem (que é do Rails e muda com o locale/versão).
class Crm::FollowUps::RecordInvalidResponse
  TEMPLATE_FALLBACK_CODE = 'template_fallback_required'.freeze
  DUE_AT_IN_THE_PAST_CODE = 'due_at_in_the_past'.freeze

  def self.render(exception)
    {
      message: exception.record.errors.full_messages.join(', '),
      attributes: exception.record.errors.attribute_names,
      code: code_for(exception.record)
    }.compact
  end

  def self.code_for(record)
    return TEMPLATE_FALLBACK_CODE if error?(record, :metadata, :template_fallback_required)

    DUE_AT_IN_THE_PAST_CODE if error?(record, :due_at, :in_the_past)
  end

  def self.error?(record, attribute, error)
    record.errors.details[attribute].to_a.any? { |detail| detail[:error] == error }
  end

  def self.template_fallback?(record)
    error?(record, :metadata, :template_fallback_required)
  end
end
