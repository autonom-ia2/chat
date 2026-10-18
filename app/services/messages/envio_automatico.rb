# Mensagem que não é uma pessoa digitando agora no painel: robô (AgentBot), assistente
# (Captain::Assistant) ou envio automático gravado em nome de uma pessoa, pela marca que cada
# um grava (regra de automação, follow-up e lembrete do CRM, convite, lembrete e aviso do
# Agendamento, campanha).
#
# A lista das marcas é única e mora em Autonomia::Agents::Operate::PessoaDaEquipe (#1710), que a
# guarda por AST (varredura_de_envios_em_nome_de_pessoa_spec) mantém em dia. Aqui só se lê.
module Messages::EnvioAutomatico
  REMETENTES_AUTOMATICOS = %w[AgentBot Captain::Assistant].freeze

  module_function

  def automatico?(message)
    REMETENTES_AUTOMATICOS.include?(message.sender_type) ||
      ::Autonomia::Agents::Operate::PessoaDaEquipe.envio_automatico?(message)
  end
end
