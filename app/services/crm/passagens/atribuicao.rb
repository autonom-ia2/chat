# O escritor único das passagens com destino PESSOA, e da devolução pela tela (#1606, contrato fixado pelo Multifunnel
# com o #1593 e o Agentes IA). Roda no Crm::PassagensListener, no despacho SÍNCRONO depois do commit, com a troca que
# a própria conversa prendeu no save (ConversationPassagem):
#
# - Uma pessoa entrou: passagem de quem estava (a pessoa anterior ou, sem ela, o robô) para ela. Motivo e card do
#   Crm::Passagens.com_motivo em curso (a Entrega, o /passar_para, o envio com "ficar com a conversa": 'ficou_ao_enviar');
#   sem ele, 'atribuicao'. Quem pediu: o robô do
#   contexto, ou a pessoa logada; nil = o sistema (o rodízio nativo, uma automação).
# - A pessoa saiu e a conversa ficou com um robô (desatribuir numa caixa com robô, inclusive o agente externo):
#   passagem da pessoa para o robô, motivo 'devolucao'. A ida para a pessoa fecha sozinha. Não grava quando o
#   PassarParaIa já gravou (com_motivo('passar_para_ia')).
# - A pessoa saiu e não ficou ninguém: encerra as passagens em aberto. A conversa resolvida também (resolvida!).
module Crm::Passagens::Atribuicao
  PASSAR_PARA_IA = 'passar_para_ia'.freeze
  ATRIBUICAO = 'atribuicao'.freeze
  DEVOLUCAO = 'devolucao'.freeze
  # #2067: a pessoa ficou com a conversa ao enviar, com o ícone "ficar com a conversa" (pedido explícito; o envio sem
  # pedido segue 'atribuicao'). Não é motivo da IA: a origem é a ponta gravada (a IA ou ninguém).
  FICOU_AO_ENVIAR = 'ficou_ao_enviar'.freeze

  module_function

  # A conversa resolvida no mesmo save encerra, qualquer que seja a troca: os after_commit rodam em ordem inversa e o
  # resolvida! pode já ter rodado antes desta troca.
  def troca!(conversation, troca)
    return if troca.nil?
    return resolvida!(conversation, troca.pedida_por) if conversation.resolved?

    pessoa = pessoa_da_conta(conversation, conversation.assignee_id)
    return pessoa_entrou!(conversation, troca, pessoa) if pessoa

    pessoa_saiu!(conversation, troca)
  end

  def resolvida!(conversation, quem)
    por = quem.is_a?(User) ? pessoa_da_conta(conversation, quem.id) : nil
    Crm::Passagens.encerrar_aberta!(conversation, por: por)
  end

  def pessoa_entrou!(conversation, troca, pessoa)
    de = pessoa_da_conta(conversation, troca.pessoa_antes_id) || robo_antes(troca)
    Crm::Passagens.registrar!(conversation: conversation, de: de, para: pessoa, pedida_por: quem_pediu(conversation, troca),
                              motivo: troca.motivo || ATRIBUICAO, card: troca.card)
  end

  def pessoa_saiu!(conversation, troca)
    antes = pessoa_da_conta(conversation, troca.pessoa_antes_id)
    return if antes.nil?

    robo = conversation.ai_assignee.is_a?(AgentBot) ? conversation.ai_assignee : nil
    pediu = quem_pediu(conversation, troca)
    return Crm::Passagens.encerrar_aberta!(conversation, por: pediu || antes) if robo.nil?
    return if troca.motivo == PASSAR_PARA_IA

    Crm::Passagens.registrar!(conversation: conversation, de: antes, para: robo, pedida_por: pediu, motivo: troca.motivo || DEVOLUCAO,
                              card: troca.card)
  end

  # Quem pediu, só se é da conta: um User de fora (o super admin pela plataforma) vira o sistema.
  def quem_pediu(conversation, troca)
    pediu = troca.pedida_por
    return pessoa_da_conta(conversation, pediu.id) if pediu.is_a?(User)

    pediu
  end

  def robo_antes(troca)
    return if troca.robo_antes_id.blank? || troca.robo_antes_type.to_s != 'AgentBot'

    AgentBot.find_by(id: troca.robo_antes_id)
  end

  def pessoa_da_conta(conversation, user_id)
    return if user_id.blank?

    conversation.account.users.find_by(id: user_id)
  end
end
