# frozen_string_literal: true

# #1657: a atribuição do rodízio nativo grava a passagem com motivo `rodizio` (Crm::Passagens::Rodizio). Por prepend;
# os serviços do Chatwoot ficam intactos. O AssignmentService já recebe o módulo do Enterprise (prepend_mod_with), e
# este vem por cima: a gravação da fila (claim_and_assign) é do OSS nos dois.
Rails.application.config.to_prepare do
  unless AutoAssignment::AgentAssignmentService <= Crm::Passagens::Rodizio::Legado
    AutoAssignment::AgentAssignmentService.prepend(Crm::Passagens::Rodizio::Legado)
  end
  AutoAssignment::AssignmentService.prepend(Crm::Passagens::Rodizio::Fila) unless AutoAssignment::AssignmentService <= Crm::Passagens::Rodizio::Fila
end
