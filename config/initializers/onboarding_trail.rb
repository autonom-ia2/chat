# frozen_string_literal: true

# A trilha de onboarding é lida de config/onboarding/trilha.yml. Validar no boot
# faz um arquivo quebrado aparecer no deploy, e não na tela do cliente.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  begin
    Onboarding::Trail.passos
  rescue Onboarding::Trail::InvalidDefinition => e
    raise e if Rails.env.development?

    Rails.logger.error("[Onboarding::Trail] trilha inválida: #{e.message}")
  end
end
