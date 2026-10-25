# Dúvida com sinal de pedido novo vira sugestão (#2162, flag `crm_ia_duvida_vira_sugestao`).
#
# Quando o modelo maior fica em dúvida, nada muda (Crm::Subjects::Identifier#revisar). Mas se alguém viu um pedido novo
# (o Jev escolheu "pedido novo" num funil, ou o modelo maior escolheu, sem certeza ou sem nome), o lead não pode sumir
# em silêncio: a equipe vê a sugestão de criar o card naquele funil, em Sugerir e em Automática, e aceita ou ignora.
# Nada é criado sozinho. Quem decide se há sinal é o modelo (a resposta dele), nunca o texto do cliente.
#
# - O funil e o nome são os do modelo maior quando ele viu o pedido novo; senão, o funil do Jev, sem nome (aceita, o
#   card nasce sem nome, e a IA de assunto dá o nome na próxima mensagem, #1918).
# - Respeita o #1260: a mesma sugestão (criar card naquele funil) que espera uma pessoa ou que ela ignorou há menos de
#   RESPEITO_AO_FECHAMENTO não volta.
# - Fica a dúvida (o lead não está sumido, ou a equipe já tem o que responder) quando a conversa tem um card aberto sem
#   nome e sem pedido (ele recebe o pedido quando ficar claro, #1918) ou quando outra sugestão já espera uma pessoa.
#
# Medição: a decisão sugerida leva `reason = MOTIVO`; o estado dela diz o que a equipe fez (suggested, accepted,
# dismissed, expired; superseded quando uma mensagem mais nova passou na frente antes de sugerir). Ver .medicao.
module Crm::Subjects::DuvidaSugerida
  FLAG = 'crm_ia_duvida_vira_sugestao'.freeze
  MOTIVO = 'duvida_pedido_novo'.freeze

  module_function

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # Quantas dúvidas a IA de assunto teve, quantas viraram sugestão, e o que a equipe fez com elas, desde `desde`.
  # Dúvida que virou sugestão não fica com o estado "doubt": as duas contagens não se sobrepõem.
  def medicao(account:, desde:)
    decisoes = Crm::SubjectDecision.where(account_id: account.id, created_at: desde..)
    sugeridas = decisoes.where(reason: MOTIVO).group(:state).count
    { duvidas_sem_sugestao: decisoes.where(state: 'doubt').count, sugeridas: sugeridas.values.sum,
      aceitas: sugeridas.fetch('accepted', 0), ignoradas: sugeridas.fetch('dismissed', 0),
      esperando: sugeridas.fetch('suggested', 0), vencidas: sugeridas.fetch('expired', 0),
      superadas: sugeridas.fetch('superseded', 0) }
  end
end
