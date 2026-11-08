# frozen_string_literal: true

# #2414 F1: a cadeia comum de automações. Ver app/services/autonomia/automacao/cadeia.rb.
Rails.application.config.to_prepare do
  {
    AsyncDispatcher => Autonomia::Automacao::CadeiaNoDespacho::Despacho,
    EventDispatcherJob => Autonomia::Automacao::CadeiaNoDespacho::Job,
    AutomationRules::ActionService => Autonomia::Automacao::CadeiaNosMotores::Regra,
    AutomationRuleListener => Autonomia::Automacao::CadeiaNosMotores::RegraDisparaRegra,
    Crm::StageAutomations::Runner => Autonomia::Automacao::CadeiaNosMotores::Etapa,
    Crm::StageAutomations::StepSequence => Autonomia::Automacao::CadeiaNosMotores::SequenciaDeEtapa,
    Crm::StageAutomationStepJob => Autonomia::Automacao::CadeiaNosMotores::PassoDeEtapa,
    Autonomia::Decisores::PerguntarJob => Autonomia::Automacao::CadeiaNosMotores::PerguntaDaRegra
  }.each { |alvo, modulo| alvo.prepend(modulo) unless alvo <= modulo }
end
