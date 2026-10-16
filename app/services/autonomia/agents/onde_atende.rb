# chat#1720 — a gaveta "Onde e quando {nome} responde" grava tudo num "Salvar" só, numa transação só:
# - "Sim, no canal X" (`primeiro`): o agente atende primeiro em X (porta). Se outro agente da plataforma atende primeiro
#   em X, ele sai, como na troca da aba "Agente de IA" (Autonomia::Agents::TrocarQuemAtende); o agente sai das outras
#   caixas em que atendia primeiro (InboxConnector, disconnect);
# - "Não, só quando alguém passar a conversa" (`primeiro` nil): sai de todas as caixas em que atende primeiro;
# - "Recebe quando alguém passar em:" (`areas`): entra (Areas.vincular!) e sai (Areas.desvincular!) das áreas. nil quando
#   a tela não mostrou a seção (sem a Fase 2 ou sem a leitura das caixas): as áreas ficam como estão;
# - o "Quando atende" (`response_window`) vai junto, quando vem.
#
# ORDEM SEGURA: primeiro tudo o que ENTRA (janela, áreas novas, a porta nova) e só depois o que SAI (portas antigas,
# áreas desmarcadas). Assim o agente nunca fica, no meio do caminho, sem onde trabalhar — o AgentInbox o pararia
# (parado_sem_onde_trabalhar, #1366). A exceção é a caixa que deixa de ser área para virar porta: o vínculo é um só
# por agente e caixa, então a área sai logo antes de a porta entrar (o `ativar` da troca liga o agente de novo, se for
# o caso). O agente só para quando a pessoa pediu "Não" sem nenhuma área E confirmou (`parar`); sem a confirmação,
# recusa antes de mexer em qualquer coisa (confirmar_parado).
#
# NADA FICA PELA METADE: tudo roda numa transação. Qualquer recusa no meio (Recusa, erro das Areas, validação) desfaz o
# que já tinha entrado; a tela recebe o código e a mensagem do passo que recusou, e "Nada mudou" é verdade.
#
# TRAVA OS AGENTES (este e o que atende primeiro em X hoje, por id) E DEPOIS AS CAIXAS (por id), a ordem dos caminhos
# da Autonom.ia (InboxConnector, Areas, TrocarQuemAtende). Quem atende primeiro em X é relido com X travada: se mudou
# entre a leitura e a trava, recusa com mudou_agora em vez de travar um agente depois de uma caixa.
class Autonomia::Agents::OndeAtende
  Resultado = Struct.new(:code, :inbox, :motivo_da_area, keyword_init: true) do
    def ok?
      code.nil?
    end
  end

  class Recusa < StandardError
    attr_reader :code, :inbox, :motivo_da_area

    def initialize(code, inbox: nil, motivo_da_area: nil)
      @code = code
      @inbox = inbox
      @motivo_da_area = motivo_da_area
      super("onde_atende refused: #{code}")
    end
  end

  # Erro das Areas -> motivo de autonomia.agents.operate.area_errors (o mesmo texto da API de canais).
  MOTIVO_DO_ERRO_DA_AREA = {
    ::Autonomia::Agents::Areas::AgenteInterno => :agent_internal,
    ::Autonomia::Agents::Areas::AgenteDeSistema => :agent_internal,
    ::Autonomia::Agents::Areas::AgenteRascunho => :rascunho,
    ::Autonomia::Agents::Areas::AgenteNaoPodeSerArea => :nao_pode_ser_area
  }.freeze
  MOTIVO_DA_CAIXA = { principal_parado: :sem_principal, robo_externo: :robo_externo }.freeze

  # `primeiro`: a caixa de "Sim, no canal", ou nil ("Não"). `areas`: as caixas de "Recebe quando alguém passar em", ou
  # nil para não mexer nelas.
  # Quem chama já achou as caixas e o agente na conta (404 fora dela).
  def initialize(agent:, primeiro:, areas:, response_window: nil, parar: false)
    @agent = agent
    @primeiro = primeiro
    @areas = areas&.uniq(&:id)
    @response_window = response_window
    @parar = parar
  end

  def perform
    ActiveRecord::Base.transaction do
      travar!
      conferir!
      gravar_janela!
      entrar_nas_areas!
      por_no_primeiro!
      sair_das_portas_antigas!
      sair_das_areas!
    end
    Resultado.new
  rescue Recusa => e
    recusada(e.code, inbox: e.inbox, motivo_da_area: e.motivo_da_area)
  rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
    recusada(:mudou_agora)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[autonomia][onde_atende] invalido model=#{e.record.class.name} account=#{@agent.account_id} agent=#{@agent.id}")
    recusada(:generico)
  end

  private

  def recusada(code, inbox: nil, motivo_da_area: nil)
    Rails.logger.warn("[autonomia][onde_atende] recusado code=#{code} account=#{@agent.account_id} agent=#{@agent.id} " \
                      "inbox=#{inbox&.id}")
    Resultado.new(code: code, inbox: inbox, motivo_da_area: motivo_da_area)
  end

  def travar!
    @porta_do_primeiro_antes = porta_do_primeiro&.autonomia_agent_id
    @travados = [@agent.id, @porta_do_primeiro_antes].compact.uniq.sort
    ::Autonomia::Agents::Agent.where(id: @travados).order(:id).lock.load
    @agent.reload
    ::Inbox.where(id: caixas_envolvidas).order(:id).lock.load
    raise Recusa, :mudou_agora if porta_do_primeiro&.autonomia_agent_id != @porta_do_primeiro_antes
  end

  def porta_do_primeiro
    return if @primeiro.nil?

    ::Autonomia::Agents::QuemAtendeACaixa.vinculos(@primeiro).porta.first
  end

  def caixas_envolvidas
    ([@primeiro&.id] + Array(@areas).map(&:id) + vinculos_do_agente.pluck(:inbox_id)).compact.uniq
  end

  def vinculos_do_agente
    ::Autonomia::Agents::AgentInbox.kept.where(autonomia_agent_id: @agent.id, account_id: @agent.account_id)
  end

  def conferir!
    recusa = recusa_do_pedido
    raise Recusa, recusa if recusa

    conferir_o_primeiro! if @primeiro
  end

  # O código da recusa que vale antes de mexer em qualquer coisa, ou nil.
  def recusa_do_pedido
    return :agente_interno if @agent.actuation_internal?

    recusa_das_areas || (:confirmar_parado if fica_parado? && !@parar)
  end

  # A caixa de "Sim" não pode estar também em "Recebe quando…"; áreas só com a Fase 2 ligada na conta.
  def recusa_das_areas
    return if @areas.blank?
    return :pedido_invalido if @primeiro && @areas.any? { |caixa| caixa.id == @primeiro.id }

    :fase2_off unless ::Autonomia::Agents::Fase2.ligada?(@agent.account)
  end

  # "Não" sem nenhuma área (as pedidas, ou as de hoje quando não vieram), tendo hoje onde trabalhar: o agente vai parar.
  def fica_parado?
    sem_areas = @areas.nil? ? !areas_atuais.exists? : @areas.empty?
    @primeiro.nil? && sem_areas && vinculos_do_agente.exists?
  end

  # A gaveta não oferece caixa com agente de outro sistema atendendo primeiro; a troca da aba da caixa tiraria ele em
  # silêncio, então aqui recusa.
  def conferir_o_primeiro!
    return unless ::Autonomia::Agents::QuemAtendeACaixa.robos_de_outro_sistema(@primeiro).exists?

    raise Recusa.new(:canal_com_outro_sistema, inbox: @primeiro)
  end

  def gravar_janela!
    return if @response_window.blank? || @agent.response_window == @response_window

    @agent.update!(response_window: @response_window)
  end

  def entrar_nas_areas!
    return if @areas.nil?

    ids_atuais = areas_atuais.pluck(:inbox_id)
    @areas.reject { |caixa| ids_atuais.include?(caixa.id) }.each { |caixa| entrar_na_area!(caixa) }
  end

  def entrar_na_area!(caixa)
    ::Autonomia::Agents::Areas.vincular!(agent: @agent, inbox: caixa)
  rescue ::Autonomia::Agents::Areas::AgenteNaoAtende
    raise Recusa, :agente_parado
  rescue ::Autonomia::Agents::Areas::CaixaNaoAceitaArea => e
    raise Recusa.new(:area_recusada, inbox: caixa, motivo_da_area: MOTIVO_DA_CAIXA.fetch(e.codigo, :generic))
  rescue *MOTIVO_DO_ERRO_DA_AREA.keys => e
    raise Recusa.new(:area_recusada, inbox: caixa, motivo_da_area: MOTIVO_DO_ERRO_DA_AREA.fetch(e.class))
  end

  def areas_atuais
    vinculos_do_agente.area
  end

  # A porta em X. Se ele está na equipe de X, sai da área logo antes (um vínculo por agente e caixa).
  def por_no_primeiro!
    return if @primeiro.nil?

    sair_da_area!(@primeiro) if areas_atuais.exists?(inbox_id: @primeiro.id)
    resultado = ::Autonomia::Agents::TrocarQuemAtende.new(inbox: @primeiro, alvo: { tipo: 'plataforma', agent: @agent }).perform
    raise Recusa.new(resultado.code == :mudou_agora ? :mudou_agora : :primeiro_recusado, inbox: @primeiro) unless resultado.ok?
  end

  def sair_das_portas_antigas!
    vinculos_do_agente.porta.where.not(inbox_id: @primeiro&.id).includes(:inbox).find_each do |vinculo|
      resultado = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inbox: vinculo.inbox).perform(connect: false)
      raise Recusa.new(:saida_recusada, inbox: vinculo.inbox) unless resultado.success?
    end
  end

  def sair_das_areas!
    return if @areas.nil?

    ids = @areas.map(&:id)
    areas_atuais.where.not(inbox_id: ids).includes(:inbox).find_each { |vinculo| sair_da_area!(vinculo.inbox) }
  end

  def sair_da_area!(caixa)
    ::Autonomia::Agents::Areas.desvincular!(agent: @agent, inbox: caixa)
  end
end
