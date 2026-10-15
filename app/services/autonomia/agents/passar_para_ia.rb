# #1593 / #1606: passar a conversa para um agente de IA. O serviço único de passagem, para quem pede: uma pessoa (na
# conversa), o CRM (pedido pelo nome, regra do funil) ou a própria IA. Quem decide que o cliente pediu um agente pelo
# nome é o modelo, nunca regex nem lista de palavras: este serviço só executa a passagem já decidida.
#
# Sem trava de tempo contra o vai e volta (decisão do Rodrigo, 15/10): a origem viaja com a passagem e o CRM a registra
# (Crm::Passagens, pelo adaptador), para a IA saber "pedido já atendido às HH:MM por X, que devolveu".
#
# A troca: o espelho do vínculo do agente NAQUELA caixa (AgentInbox, nunca o Crm::Ai::Config) vira o ai_assignee, pelo
# AssignmentService da atribuição manual, com a conversa travada e relida. Na mesma gravação o AssignmentService encerra a
# espera de pessoa e a marca do motor de entrega (`end_bot_handoff_wait`) e tira a pessoa da conversa (só
# `por: :pessoa` chega aqui com pessoa no nome; CRM e IA são recusados com `pessoa_atribuida`). O registro da
# passagem vem depois, na mesma transação. Depois do commit sai o `crm.ai.responsible_agent_changed`, o mesmo do Sync do
# CRM, e o assinante (Operate::ReenfileirarTurno) refaz o turno em andamento com o dono novo.
module Autonomia::Agents::PassarParaIa
  POR = %i[pessoa crm ia].freeze
  # O contexto do registro do CRM em que a passagem é gravada por este serviço (Crm::Passagens.com_motivo).
  MOTIVO_DO_REGISTRO = 'passar_para_ia'.freeze
  CODIGOS = %i[passou ja_e_o_dono fase2_desligada nao_atende_cliente sem_vinculo_na_caixa outra_conta
               conversa_resolvida pessoa_atribuida].freeze

  # `ok?` também é verdadeiro quando o agente já era o dono (`ja_e_o_dono`, nada troca).
  Resultado = Struct.new(:ok, :trocou, :codigo, keyword_init: true) do
    def self.passou = new(ok: true, trocou: true, codigo: :passou)
    def self.ja_e_o_dono = new(ok: true, trocou: false, codigo: :ja_e_o_dono)
    def self.recusa(codigo) = new(ok: false, trocou: false, codigo: codigo)

    def ok? = ok
    def trocou? = trocou
  end

  module_function

  # origem: quem tinha a conversa (User, Autonomia::Agents::Agent ou AgentBot), ou nil. A assinatura é o contrato
  # fixado com o Multifunnel (#1593).
  def call(conversation:, agent:, por:, motivo:, origem: nil, transfer_id: nil) # rubocop:disable Metrics/ParameterLists
    raise ArgumentError, "por fora da lista: #{por}" unless POR.include?(por)

    pedido = { agent: agent, por: por, motivo: motivo, origem: origem, transfer_id: transfer_id }
    codigo = recusa_antes_da_trava(conversation, agent)
    resultado = codigo ? Resultado.recusa(codigo) : passar(conversation, pedido)
    registrar_telemetria(conversation, resultado, por)
    resultado
  end

  # Os agentes que podem receber conversas desta caixa: vínculo ativo (porta ou área) e atendendo cliente. Só com a
  # Fase 2 ligada na conta da caixa. Uma consulta para os vínculos, com os agentes junto.
  def destinos_na_caixa(inbox)
    return [] if inbox.blank? || !fase2?(inbox.account)

    ::Autonomia::Agents::AgentInbox.kept.where(inbox_id: inbox.id, account_id: inbox.account_id)
                                   .includes(:agent).order(:id).filter_map(&:agent)
                                   .select { |agente| agente.account_id == inbox.account_id && agente.atende_cliente? }
  end

  # Os da caixa da conversa, menos o que a conversa não permite: resolvida não recebe ninguém.
  def destinos_possiveis(conversation)
    return [] if conversation.blank? || conversation.resolved?

    destinos_na_caixa(conversation.inbox)
  end

  def fase2?(account)
    ::Autonomia::Agents::Config.enabled?(account) && ::Autonomia::Agents::Fase2.ligada?(account)
  end

  def recusa_antes_da_trava(conversation, agent)
    return :outra_conta if agent.account_id != conversation.account_id
    return :fase2_desligada unless fase2?(conversation.account)

    :nao_atende_cliente unless agent.atende_cliente?
  end

  # Tudo relido sob a trava. Sem return dentro do with_lock (dispararia ROLLBACK): o resultado sai em variável.
  def passar(conversation, pedido)
    resultado = nil
    de = nil
    conversation.with_lock do
      vinculo = vinculo_na_caixa(conversation, pedido[:agent])
      resultado = decidir(conversation, vinculo, pedido[:por])
      if resultado.trocou?
        de = conversation.ai_assignee
        trocar_e_registrar!(conversation, vinculo, pedido)
      end
    end
    publicar(conversation, de, pedido) if resultado.trocou?
    resultado
  end

  def vinculo_na_caixa(conversation, agent)
    ::Autonomia::Agents::AgentInbox.kept.find_by(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                                 autonomia_agent_id: agent.id)
  end

  # Pessoa no nome vence (decisão "a" do Rodrigo, 15/10, e "atendente responde não assume"): só ela mesma, ou outra
  # pessoa pela tela (`por: :pessoa`), passa a conversa para a IA. O CRM e a IA não tiram a conversa de uma pessoa.
  def decidir(conversation, vinculo, por)
    return Resultado.recusa(:conversa_resolvida) if conversation.resolved?
    return Resultado.recusa(:pessoa_atribuida) if conversation.assignee_id.present? && por != :pessoa
    return Resultado.recusa(:sem_vinculo_na_caixa) if vinculo.nil?
    return Resultado.ja_e_o_dono if conversation.assignee_id.nil? && conversation.ai_assignee == vinculo.agent_bot

    Resultado.passou
  end

  # O AssignmentService de robô tira a pessoa, põe o espelho, abre a conversa e encerra as esperas (end_bot_handoff_wait),
  # numa gravação; o registro da passagem vem logo depois, na mesma transação. Tudo dentro do `com_motivo` do CRM: o
  # listener síncrono dele vê que esta passagem já está sendo gravada aqui e não grava outra.
  def trocar_e_registrar!(conversation, vinculo, pedido)
    contrato = ::Autonomia::Agents::ContratoDoFunil
    contrato.com_motivo_da_passagem(MOTIVO_DO_REGISTRO) do
      ::Conversations::AssignmentService.new(conversation: conversation, assignee_id: vinculo.agent_bot_id,
                                             assignee_type: 'AgentBot').perform
      contrato.registrar_passagem!(conversation: conversation, de: pedido[:origem], para: pedido[:agent],
                                   pedida_por: pedida_por(pedido), motivo: pedido[:motivo], transfer_id: pedido[:transfer_id])
    end
  end

  # Quem pediu, no formato do registro (User, Agent, AgentBot ou nil = o sistema). Pedido do CRM é do sistema; de pessoa
  # ou da IA, quem tinha a conversa e a passou.
  def pedida_por(pedido)
    pedido[:por] == :crm ? nil : pedido[:origem]
  end

  def publicar(conversation, anterior, pedido)
    evento = { conversation: conversation, from_bot: anterior.is_a?(AgentBot) ? anterior : nil, to_bot: conversation.ai_assignee,
               agent: pedido[:agent], transfer_id: pedido[:transfer_id], motivo: pedido[:motivo], origem: pedido[:origem],
               por: pedido[:por] }
    ActiveRecord.after_all_transactions_commit do
      ActiveSupport::Notifications.instrument(::Crm::Ai::ResponsibleAgentSync::EVENTO_TROCA, evento)
    end
  end

  def registrar_telemetria(conversation, resultado, por)
    evento = resultado.ok? ? :passagem : :passagem_recusada
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(evento, conversation_id: conversation.id,
                                                                      codigo: resultado.codigo, por: por)
  end
end
