# O passo `perguntar_ao_decisor` de uma automação (#858), fora do EventDispatcherJob.
#
# Reaproveita a decisão já guardada para a mesma mensagem, ou pergunta ao Jev. Se a resposta é a chave
# que segue, com certeza suficiente, grava os campos e retoma a automação em `indice + 1`. Outra
# resposta para; dúvida vai ao Guia (DuvidaJob), que volta aqui quando decide.
#
# Volta aqui também quando a pessoa resolve um caso parado: a decisão já estará `resolvida`.
class Autonomia::Decisores::PerguntarJob < ApplicationJob
  queue_as :medium

  # O cliente do Jev já tenta 3 vezes por chamada. Estes são os erros que valem esperar e tentar de novo;
  # chave inválida ou resposta fora do contrato não melhoram com o tempo.
  TRANSITORIOS = %w[typesafe_unavailable typesafe_rate_limited typesafe_overloaded].freeze
  JevIndisponivel = Class.new(StandardError)

  retry_on JevIndisponivel, wait: 1.minute, attempts: 3 do |job, error|
    Rails.logger.warn("[autonomia][decisor] regra=#{job.arguments.first} Jev indisponível, desisti: #{error.message}")
  end

  def perform(rule_id, conversation_id, message_id, indice)
    rule = AutomationRule.find_by(id: rule_id)
    return unless rule&.active?

    decisor_id, chave = passo(rule, indice)
    decisor = Autonomia::Decisor.find_by(id: decisor_id.to_s, account_id: rule.account_id)
    conversation = rule.account.conversations.find_by(id: conversation_id)
    message = conversation&.messages&.find_by(id: message_id)
    return if decisor.blank? || message.blank?

    decidir(rule, decisor, message, indice, chave)
  end

  private

  def decidir(rule, decisor, message, indice, chave)
    decisao = Autonomia::Decisores::Pergunta.new(decisor: decisor, conversation: message.conversation, message: message,
                                                 rule: rule, indice: indice).decisao
    return unless decisao.decidida? && decisao.resposta == chave.to_s

    Autonomia::Decisores::Seguimento.new(decisao: decisao, rule: rule, conversation: message.conversation,
                                         message: message, indice: indice).perform
  rescue TypesafeAi::Decisor::Error => e
    raise JevIndisponivel, e.code if TRANSITORIOS.include?(e.code)

    Rails.logger.warn("[autonomia][decisor] regra=#{rule.id} decisor=#{decisor.id} Jev recusou: #{e.code}")
  end

  # A regra pode ter mudado entre o enfileiramento e agora: só vale se o passo continua sendo o do Decisor.
  def passo(rule, indice)
    action = rule.actions[indice].to_h.with_indifferent_access
    return [] unless action[:action_name] == Autonomia::Decisores::PASSO

    Array(action[:action_params])
  end
end
