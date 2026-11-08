# "Um turno, uma ordem" (#1606): os leitores que a metade Multifunnel expõe e que os Agentes só LEEM. Todo lugar dos
# Agentes que precisa deles passa por aqui, nunca pela constante do CRM direto:
# - `ordem_do_turno?(conversation)`  -> este turno espera o assunto ser decidido? (Crm::Subjects.ordem_do_turno?)
# - `decidido_ate(conversation_id)`  -> até que mensagem o assunto já foi decidido E o Sync aplicado, ou nil
#                                      (Crm::Subjects::Marco.decidido_ate)
# - `robo_do_funil(conversation)`    -> o espelho de área do responsável do funil do card em atendimento, ou nil
#                                      (Crm::Ai::Config.robo_do_funil)
# - `registrar_passagem!(...)`       -> grava a passagem no registro do CRM (Crm::Passagens.registrar!)
# - `com_motivo_da_passagem(motivo, card:)` -> roda o bloco com motivo e card guardados no contexto do CRM
#                                      (Crm::Passagens.com_motivo(motivo, card: nil) { ... }, devolve o valor do bloco),
#                                      para o listener dele saber que a passagem já é gravada por quem chama
# - `avaliar_depois_da_fala(conversation)` -> pede a avaliação da IA de Atribuição depois que saiu a fala do agente que
#                                      avisou que vai chamar alguém (#2154, Crm::Ai::AvaliacaoDepoisDaFala.agendar)
#
# Nos specs, duble ESTE módulo (`allow(described_class)...`), nunca a presença ou a ausência da constante do CRM.
module Autonomia::Agents::ContratoDoFunil
  LEITORES = {
    ordem_do_turno?: ['Crm::Subjects', :ordem_do_turno?],
    decidido_ate: ['Crm::Subjects::Marco', :decidido_ate],
    robo_do_funil: ['Crm::Ai::Config', :robo_do_funil],
    registrar_passagem!: ['Crm::Passagens', :registrar!],
    com_motivo_da_passagem: ['Crm::Passagens', :com_motivo],
    avaliar_depois_da_fala: ['Crm::Ai::AvaliacaoDepoisDaFala', :agendar]
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

  # Assinatura do Crm::Passagens.registrar! (PR #1611). `message_id` fica com o padrão do CRM; card nil = sem card.
  # rubocop:disable Naming/MethodParameterName, Metrics/ParameterLists
  def registrar_passagem!(conversation:, de:, para:, pedida_por:, motivo:, card: nil, transfer_id: nil)
    leitor = leitor_do(:registrar_passagem!)
    leitor&.registrar!(conversation: conversation, de: de, para: para, pedida_por: pedida_por, motivo: motivo, card: card,
                       transfer_id: transfer_id)
  end
  # rubocop:enable Naming/MethodParameterName, Metrics/ParameterLists

  # Decidido na hora da chamada (leitor_do), nunca no carregamento: sem o com_motivo do CRM, o bloco roda direto.
  def com_motivo_da_passagem(motivo, card: nil, &)
    leitor = leitor_do(:com_motivo_da_passagem)
    leitor ? leitor.com_motivo(motivo, card: card, &) : yield
  end

  # #2154: sem o leitor do CRM, ninguém avalia (nil) e o agente segue atendendo.
  def avaliar_depois_da_fala(conversation)
    leitor_do(:avaliar_depois_da_fala)&.agendar(conversation)
  end

  # PADRÃO SEGURO, num lugar só. Enquanto a metade Multifunnel não está na main, o leitor não existe e a resposta é a
  # de hoje: o turno não espera (false), não há marco (nil), a devolução vai para a porta (nil), a passagem não é
  # registrada e o bloco do `com_motivo` roda direto. Remover este fallback quando os leitores estiverem na main:
  # autonom-ia2/chat#1610.
  def leitor_do(nome)
    constante, metodo = LEITORES.fetch(nome)
    alvo = constante.safe_constantize
    alvo if alvo.respond_to?(metodo)
  end
  private_class_method :leitor_do
end
