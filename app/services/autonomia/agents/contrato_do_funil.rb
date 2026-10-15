# "Um turno, uma ordem" (#1606): os leitores que a metade Multifunnel expõe e que os Agentes só LEEM. Todo lugar dos
# Agentes que precisa deles passa por aqui, nunca pela constante do CRM direto:
# - `ordem_do_turno?(conversation)`  -> este turno espera o assunto ser decidido? (Crm::Subjects.ordem_do_turno?)
# - `decidido_ate(conversation_id)`  -> até que mensagem o assunto já foi decidido E o Sync aplicado, ou nil
#                                      (Crm::Subjects::Marco.decidido_ate)
# - `robo_do_funil(conversation)`    -> o espelho de área do responsável do funil do card em atendimento, ou nil
#                                      (Crm::Ai::Config.robo_do_funil)
#
# Nos specs, duble ESTE módulo (`allow(described_class)...`), nunca a presença ou a ausência da constante do CRM.
module Autonomia::Agents::ContratoDoFunil
  LEITORES = {
    ordem_do_turno?: ['Crm::Subjects', :ordem_do_turno?],
    decidido_ate: ['Crm::Subjects::Marco', :decidido_ate],
    robo_do_funil: ['Crm::Ai::Config', :robo_do_funil]
  }.freeze

  module_function

  def ordem_do_turno?(conversation)
    leitor = leitor_do(:ordem_do_turno?)
    leitor ? leitor.ordem_do_turno?(conversation) == true : false
  end

  def decidido_ate(conversation_id)
    leitor = leitor_do(:decidido_ate)
    leitor&.decidido_ate(conversation_id)&.to_i
  end

  def robo_do_funil(conversation)
    leitor = leitor_do(:robo_do_funil)
    robo = leitor&.robo_do_funil(conversation)
    robo.is_a?(AgentBot) ? robo : nil
  end

  # PADRÃO SEGURO, num lugar só. Enquanto a metade Multifunnel não está na main, o leitor não existe e a resposta é a
  # de hoje: o turno não espera (false), não há marco (nil) e a devolução vai para a porta (nil). Remover este fallback
  # quando os três leitores estiverem na main: autonom-ia2/chat#1610.
  def leitor_do(nome)
    constante, metodo = LEITORES.fetch(nome)
    alvo = constante.safe_constantize
    alvo if alvo.respond_to?(metodo)
  end
  private_class_method :leitor_do
end
