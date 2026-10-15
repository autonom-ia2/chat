# chat#1648 — "Quem atende primeiro" da aba "Agente de IA" da caixa: a troca COMPLETA, numa transação só.
# Tira quem atende primeiro hoje pelo caminho certo e põe o novo:
# - agente da plataforma sai pelo InboxConnector (disconnect): as conversas dele voltam para a equipe, as ÁREAS da caixa
#   ficam (#1621, a caixa passa a ser só de pessoas até o novo entrar) e, sendo a última caixa dele, ele para (#1366);
# - agente de outro sistema (AgentBotInbox de um AgentBot que não é espelho) sai apagando o AgentBotInbox, e as conversas
#   que ele segurava voltam para a equipe pela mesma regra da porta (pending sem dono ou dele, open dele);
# - agente da plataforma entra pelo InboxConnector (connect), com as regras dele; parado sem onde trabalhar, entra e liga
#   (`ativar`, #1366);
# - agente de outro sistema entra com um AgentBotInbox, gravado aqui e não pelo set_agent_bot: o prepend
#   CaixaSemAgenteExterno continua protegendo a API crua. As áreas da caixa ficam e continuam recebendo quando alguém
#   passa (decisão do Rodrigo de 15/10, opção B; o risco de os dois responderem quando o outro sistema não filtra por
#   dono ficou na #1636).
#
# `alvo`: { tipo: 'plataforma', agent: } | { tipo: 'webhook', agent_bot: } | { tipo: 'nenhum' }. Quem chama já achou o
# agente na conta (404 fora dela). Pedido igual ao estado atual não muda nada (idempotente).
#
# Recusas, com o código de Resultado#code (a tela mostra o motivo):
# - agente_interno / agente_rascunho / agente_parado: o agente da plataforma não pode atender cliente nesta caixa agora
#   (mesmo predicado do agente da equipe, Agent#motivo_para_nao_ser_area: interno, rascunho, parado de propósito);
# - agente_ja_e_da_equipe: o agente já recebe quando alguém passa nesta caixa (área). Recusa em vez de converter a área em
#   porta: converter passaria pelo Areas.desvincular! (devolve as conversas da área para a porta que está saindo e, sendo a
#   última caixa dele, PARA o agente) antes do connect, misturando dois ciclos de vida numa troca só;
# - mudou_agora: outro caminho pôs um agente nesta caixa entre a leitura e a trava (a tela relê e a pessoa tenta de novo);
# - conexao_recusada: o InboxConnector recusou por outro motivo.
#
# TRAVA OS AGENTES (o que sai e o que entra, por id) E DEPOIS A CAIXA, a ordem dos caminhos da Autonom.ia (InboxConnector,
# Areas, SoftDelete, CaixaSemAgenteExterno). Quem sai é relido com a caixa travada: se não é um dos agentes travados,
# recusa com mudou_agora em vez de travar um agente depois da caixa.
class Autonomia::Agents::TrocarQuemAtende
  Resultado = Struct.new(:code, :mudou, keyword_init: true) do
    def ok?
      code.nil?
    end
  end

  class Recusa < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super("quem_atende refused: #{code}")
    end
  end

  RECUSA_DO_AGENTE = { interno: :agente_interno, sistema: :agente_interno, rascunho: :agente_rascunho,
                       fora_da_equipe: :agente_parado }.freeze

  def initialize(inbox:, alvo:)
    @inbox = inbox
    @alvo = alvo
    @novo_agente = alvo[:agent]
    @novo_robo = alvo[:agent_bot]
  end

  def perform
    mudou = ActiveRecord::Base.transaction do
      travar!
      @atual = ler_a_caixa
      next false if igual_ao_atual?

      conferir_o_novo!
      tirar_o_atual!
      por_o_novo!
      true
    end
    Resultado.new(mudou: mudou)
  rescue Recusa => e
    Rails.logger.warn("[autonomia][quem_atende] recusado code=#{e.code} account=#{@inbox.account_id} inbox=#{@inbox.id}")
    Resultado.new(code: e.code, mudou: false)
  end

  private

  def travar!
    @travados = ([porta_lida_antes&.autonomia_agent_id, @novo_agente&.id].compact.uniq.sort)
    ::Autonomia::Agents::Agent.where(id: @travados).order(:id).lock.load
    ::Inbox.lock.find(@inbox.id)
  end

  def porta_lida_antes
    ::Autonomia::Agents::QuemAtendeACaixa.vinculos(@inbox).porta.first
  end

  # O estado da caixa com ela travada: a porta (AgentInbox) e os AgentBotInbox de outro sistema.
  def ler_a_caixa
    porta = ::Autonomia::Agents::QuemAtendeACaixa.vinculos(@inbox).porta.includes(:agent).first
    raise Recusa, :mudou_agora if porta && @travados.exclude?(porta.autonomia_agent_id)

    { porta: porta, robos: ::Autonomia::Agents::QuemAtendeACaixa.robos_de_outro_sistema(@inbox).to_a }
  end

  def igual_ao_atual?
    robos = @atual[:robos].map(&:agent_bot_id)
    case @alvo[:tipo]
    when 'plataforma' then atende_primeiro_agora? && robos.empty?
    when 'webhook' then @atual[:porta].nil? && robos == [@novo_robo.id]
    else @atual[:porta].nil? && robos.empty?
    end
  end

  def conferir_o_novo!
    conferir_agente! if @alvo[:tipo] == 'plataforma'
  end

  def conferir_agente!
    @novo_agente.reload
    motivo = @novo_agente.motivo_para_nao_ser_area unless atende_primeiro_agora?
    raise Recusa, RECUSA_DO_AGENTE.fetch(motivo) if motivo
    raise Recusa, :agente_ja_e_da_equipe if areas.exists?(autonomia_agent_id: @novo_agente.id)
  end

  # Já é a porta (com um agente de outro sistema sobrando na caixa): fica, e só o outro sai.
  def atende_primeiro_agora?
    @atual[:porta]&.autonomia_agent_id == @novo_agente.id
  end

  def areas
    ::Autonomia::Agents::QuemAtendeACaixa.vinculos(@inbox).area
  end

  def tirar_o_atual!
    porta = @atual[:porta]
    desconectar!(porta.agent) if porta && !(@alvo[:tipo] == 'plataforma' && atende_primeiro_agora?)
    @atual[:robos].each { |bot_inbox| tirar_robo!(bot_inbox) }
  end

  def desconectar!(agente)
    resultado = conector(agente).perform(connect: false)
    raise Recusa, :conexao_recusada unless resultado.success?
  end

  # As conversas que o agente de outro sistema segurava voltam para a equipe, pela regra da porta
  # (AgentInbox#release_bot_conversations!): pending sem dono ou dele, open dele.
  def tirar_robo!(bot_inbox)
    bot_inbox.destroy!
    pending = @inbox.conversations.where(status: :pending, assignee_agent_bot_id: [nil, bot_inbox.agent_bot_id])
    dele = @inbox.conversations.where(status: :open, assignee_agent_bot_id: bot_inbox.agent_bot_id)
    pending.or(dele).find_each { |conversation| conversation.bot_handoff!(keep_bot: false) }
  end

  def por_o_novo!
    case @alvo[:tipo]
    when 'plataforma' then conectar! unless atende_primeiro_agora?
    when 'webhook' then AgentBotInbox.create!(inbox: @inbox, agent_bot: @novo_robo, account: @inbox.account)
    end
  end

  def conectar!
    resultado = conector(@novo_agente, ativar: !@novo_agente.operating?).perform(connect: true)
    return if resultado.success?

    raise Recusa, resultado.error == :agent_internal_not_connectable ? :agente_interno : :conexao_recusada
  end

  def conector(agente, ativar: false)
    ::Autonomia::Agents::Operate::InboxConnector.new(agent: agente, inbox: @inbox, ativar: ativar)
  end
end
