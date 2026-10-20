# MOTOR ÚNICO DE ENTREGA (#1454, decisões do Rodrigo em 13/10/2026). Decide QUEM atende agora uma conversa que precisa
# de uma pessoa, sem depender do rodízio nativo da caixa:
#
#   Crm::Entrega.new(conversation:, motivo:, origem:).call
#
# - Com card aberto e a Atribuição do funil ligada (Crm::Ai::Config.handoff_settings, a etapa vence o funil): segue a
#   regra. Pessoa de quem cuida do funil com menos conversas abertas (ou a pessoa fixa, que cai para a fila se não puder
#   receber), convite, ou segurar até alguém ficar online ("Só entregar para quem está online").
# - Sem card, sem CRM ou com a regra desligada: quem cuida da conversa (Crm::Entrega::QuemCuida) e está online, com
#   menos conversas abertas. Ninguém online: segura.
# - Segurar e convidar deixam a marca Crm::Entrega::Marca na conversa: o rodízio nativo a pula, e o
#   Crm::Ai::HandoffDrainJob tenta de novo a cada 2 minutos.
#
# Trava sempre a conversa e só depois o card, a mesma ordem do CardSyncer e dos jobs da passagem (sem deadlock ABBA).
# Relê a conversa sob a trava: quem atribuiu antes (uma pessoa, o rodízio nativo, outra entrega) vence, e a entrega
# não grava nada por cima.
#
# Quem chama: ConversationBotHandoff#bot_handoff! (o robô do Agentes IA, o n8n por toggle_status e quem desliga o
# robô), a saída da triagem (Crm::Access::TriageExit / VisibilitySync), a IA do CRM (Crm::Ai::HandoffExecutor, que é
# só o adaptador dela) e a fila de quem espera (HandoffDrainJob).
#
# Agente de IA (#1593): quando a regra aponta um agente que pode receber na caixa (Crm::Entrega::ParaIa), o plano é
# `:ia`. A passagem para ele é do serviço dos Agentes, que trava e relê por conta própria; por isso ela acontece DEPOIS
# da trava: em `call`, logo em seguida; na passagem do robô, o resultado sai `:para_ia` e o
# ConversationBotHandoff chama `concluir_para_ia!` depois do commit. Recusada (o agente parou entre a leitura e a
# passagem, por exemplo), a entrega roda de novo sem IA: alguém da equipe.
class Crm::Entrega # rubocop:disable Metrics/ClassLength -- #pode_entregar_agora? (#1975) usa o mesmo #planejar; fora daqui duplicaria a regra
  Resultado = Struct.new(:status, :pessoa, :motivo, :card, :agente, keyword_init: true)
  Plano = Struct.new(:acao, :pessoa, :card, :settings, :motivo, :agente, keyword_init: true)
  # Motivos em que quem pediu a passagem foi o robô que atendia.
  PEDIDO_DO_ROBO = %w[robo_pediu n8n].freeze
  # A fila segura a espera da IA do CRM até a releitura (#1975).
  AGUARDANDO_RELEITURA = 'aguardando_releitura'.freeze

  # `pedido`: o que a IA do CRM pediu, quando é ela que chama (`sugestao`: o nome que ela sugeriu, para a regra
  # "direto"; `razao`: o motivo dela, para a linha do tempo do card). `quem_passou`: o robô que está passando, na
  # passagem do robô (ConversationBotHandoff#bot_handoff!), que pode ser o da caixa quando a conversa não tinha robô.
  # `dono`: a pessoa a quem a conversa é dirigida (o dono do card, R13 do #1150), se está na fila de quem cuida (ver
  # #fila). Sem regra no funil, a conversa espera por ela (a marca guarda o dono para a próxima tentativa); com regra, ela
  # recebe (ou é convidada) quando está online, e nem o agente de IA da regra entra; offline, a regra decide, inclusive
  # passando ao agente de IA. Fora da fila (sem o funil, saiu da caixa), vale a fila de sempre.
  # `pelo_card` (#1693, decisão 1a do Rodrigo, 16/10): a regra é a do `card` (o assunto a que o cliente ligou o pedido),
  # e não a do assunto em foco, enquanto ele seguir aberto nesta conversa. Segurada ou convidada, a marca guarda o card
  # para a fila e para o convite vencido.
  # `exigir_releitura` (#1975, só a fila): a espera da IA do CRM que ainda não foi relida não sai sem a releitura
  # (#sem_entregar_antes_de_reler).
  # `excluir`: ids de quem deixou um convite desta espera vencer (#1694, decisão do Rodrigo de 16/10): com regra, ficam
  # fora da fila. Se eram todos, sem convite novo: a conversa vai ao primeiro de quem cuida que ficar online (#pela_regra).
  # rubocop:disable Metrics/ParameterLists
  def initialize(conversation:, motivo:, origem:, card: nil, pedido: {}, quem_passou: nil, dono: nil, pelo_card: false, excluir: [],
                 exigir_releitura: false)
    @conversation = conversation
    @exigir_releitura = exigir_releitura
    @pelo_card = pelo_card
    @motivo = motivo.to_s
    @origem = origem.to_s
    @card = card
    @sugestao = pedido[:sugestao]
    @razao = pedido[:razao]
    @quem_passou = quem_passou
    @dono = Crm::Entrega::Dono.new(conversation: conversation, pessoa: dono, excluir: excluir)
  end
  # rubocop:enable Metrics/ParameterLists

  # Por conta própria: trava a conversa, relê e grava.
  def call
    Crm::Passagens.com_motivo(@motivo) do
      @conversation.with_lock { @resultado = executar(sem_entregar_antes_de_reler(planejar), gravar: true) }
    end
    registrar
    @resultado.status == :para_ia ? concluir_para_ia! : @resultado
  end

  # Dentro de ConversationBotHandoff#bot_handoff!, com a linha já travada: a passagem grava status, robô e pessoa numa
  # gravação só (os callbacks veem a troca de status e a de atendente juntas). Aqui a conversa muda só na memória.
  # `:para_ia`: quem chama termina com `concluir_para_ia!` depois do commit.
  def na_passagem
    @resultado = executar(planejar, gravar: false)
    registrar
    @resultado
  end

  # Para a fila (#1975, Crm::Ai::RevalidacaoNaFila): a entrega sairia agora (para uma pessoa, um convite fora do
  # intervalo ou um agente de IA)? Só lê, sem trava e sem gravar, com a mesma regra, os mesmos impedimentos e a presença
  # da rodada (Crm::Entrega::Presenca) que o #call usa logo depois.
  def pode_entregar_agora? = entregaria?(planejar)

  # O card cuja regra vale (#1606, #1693): o do pedido (`pelo_card`), enquanto seguir aberto nesta conversa, em foco ou
  # não; senão o assunto em foco (`atual`). A fila (Crm::Ai::RevalidacaoNaFila) usa o mesmo caminho.
  def self.card_da_regra(conversation, card:, pelo_card:, atual: Crm::Assunto.funil_atual(conversation))
    pelo_card && Crm::Assunto.da_conversa?(card, conversation) ? card : atual
  end

  # Fora de qualquer trava: o serviço dos Agentes trava a conversa e relê. A origem é o robô que estava com a conversa
  # (o que passou). Só 'passou' é a IA assumindo. 'pessoa_atribuida': uma pessoa entrou no nome antes; ela fica com a
  # conversa e nada muda. As recusas: alguém da equipe. O agente que está com a conversa nem chega aqui: o `alvo` o tira
  # do plano, e a regra cai para pessoas (a IA do CRM pedindo transferência com o agente no comando é pedido de pessoa).
  # 'ja_e_o_dono' só vem de uma corrida (outra passagem pôs o agente no nome entre o plano e o serviço) e também vai
  # para a equipe; se o serviço levantar depois de trocar, o ParaIa relê e conta a troca feita ('passou'). A
  # diferença entre as duas corridas é aceita: as duas terminam com um dono só.
  def concluir_para_ia!(origem: @conversation.ai_assignee)
    agente = @resultado.agente
    codigo = Crm::Entrega::ParaIa.pela_atribuicao!(conversation: @conversation, agent: agente, origem: origem,
                                                   rotulo: "motivo=#{@motivo} origem=#{@origem}")
    return Resultado.new(status: :com_ia, agente: agente, card: @resultado.card) if codigo == Crm::Entrega::ParaIa::PASSOU
    return Resultado.new(status: :nada, motivo: 'ja_tem_pessoa', card: @resultado.card) if codigo == Crm::Entrega::ParaIa::FICA_COM_A_PESSOA

    @sem_ia = true
    @conversation.reload
    call
  end

  private

  # O plano entregaria agora? Pessoa e agente de IA, sim; o convite, se o intervalo entre passagens não o barra (a mesma
  # checagem do #convite_no_card).
  def entregaria?(plano)
    case plano.acao
    when :pessoa, :ia then true
    when :convite then !convite_no_intervalo?(plano)
    else false
    end
  end

  # Pela fila (#1975, `exigir_releitura`): a espera da IA do CRM que ainda não foi relida desde a última mensagem
  # (Crm::Ai::RevalidacaoNaFila#falta_reler?) não sai, mesmo que alguém tenha entrado entre a consulta da fila e aqui:
  # segura, e a rodada seguinte relê.
  def sem_entregar_antes_de_reler(plano)
    return plano unless @exigir_releitura && entregaria?(plano) && Crm::Ai::RevalidacaoNaFila.new(@conversation).falta_reler?

    Plano.new(acao: :segurar, card: plano.card, settings: plano.settings, motivo: AGUARDANDO_RELEITURA)
  end

  def planejar
    @quem_atendia ||= robo_que_atendia
    return nada('ja_tem_pessoa') if @conversation.assignee_id.present?
    return nada('fechada') unless @conversation.open? || @conversation.pending?

    card = card_em_atendimento
    settings = regra_do(card)
    return sem_regra(card) unless settings

    agente = agente_da_regra(card, settings)
    return Plano.new(acao: :ia, agente: agente, card: card, settings: settings) if agente

    pela_regra(card, Crm::Entrega::ParaIa.so_pessoas(settings))
  end

  # O agente de IA que a regra aponta e pode receber agora; nunca o robô que está passando (Crm::Entrega::ParaIa.alvo).
  # A entrega dirigida ao dono do card que pode receber (R13, Crm::Entrega::Dono) passa na frente dele.
  def agente_da_regra(card, settings)
    return if @sem_ia || @dono.na_frente? { fila(card, settings) }

    Crm::Entrega::ParaIa.alvo(conversation: @conversation, settings: settings, sugestao: @sugestao, quem_passa: @quem_passou || @quem_atendia)
  end

  # Todos que cuidam deixaram um convite desta espera vencer (#1694, opção "a"): sem convite novo, a conversa vai para o
  # primeiro deles que ficar online (Crm::Entrega::Dono#so_quem_venceu?), como no segurar de sempre.
  def pela_regra(card, settings)
    membros = fila(card, settings)
    convite = settings[:handoff_mode] == 'r3_invite' && !@dono.so_quem_venceu?
    selector = seletor(settings, require_online: !convite && (settings[:prefer_online] || @dono.so_quem_venceu?), membros: membros)
    escolher(selector, card, settings, acao: convite ? :convite : :pessoa)
  end

  # Sem regra: quem cuida da conversa e está online, com menos conversas abertas (decisão 2 do Rodrigo, 13/10).
  def sem_regra(card)
    selector = Crm::Ai::HandoffMemberSelector.new(
      inbox: @conversation.inbox, account_id: @conversation.account_id, members: fila(card, nil),
      mode: 'round_robin', prefer_online: true, require_online: true, conversation: @conversation
    )
    escolher(selector, card, nil)
  end

  # Ninguém que possa receber agora (ninguém online, ninguém na fila deste assunto, nem para convidar, ou a presença fora
  # do ar): segura, com a marca. O rodízio nativo não passa por cima, e a fila tenta de novo a cada 2 minutos e entrega
  # quando alguém entrar ou passar a cuidar do assunto. Nunca silêncio.
  def escolher(selector, card, settings, acao: :pessoa)
    pessoa = selector.perform
    return Plano.new(acao: acao, pessoa: pessoa, card: card, settings: settings) if pessoa

    Plano.new(acao: :segurar, card: card, settings: settings, motivo: selector.held_for_online? ? 'ninguem_online' : 'ninguem_cuida')
  rescue Crm::Ai::HandoffMemberSelector::PresencaIndisponivel
    Plano.new(acao: :segurar, card: card, settings: settings, motivo: 'presenca_indisponivel')
  end

  # O nome pedido que era de um agente de IA que não pôde receber não é nome de pessoa para casar.
  def seletor(settings, require_online:, membros:)
    sugestao = Crm::AgentesIa.rotulo_de_agente?(@sugestao) ? nil : @sugestao
    Crm::Ai::HandoffMemberSelector.new(
      inbox: @conversation.inbox, account_id: @conversation.account_id, members: membros,
      mode: settings[:selector_mode], prefer_online: settings[:prefer_online], require_online: require_online || @dono.sem_presenca?,
      suggested_name: sugestao, pool_type: @dono.so_quem_venceu? ? 'inbox' : settings[:pool_type], pool_id: settings[:pool_id],
      conversation: @conversation
    )
  end

  # Quem cuida (Crm::Entrega::QuemCuida), menos quem deixou um convite desta espera vencer (#1694; todos: ver
  # #pela_regra), ou só o dono quando
  # a entrega é dirigida a ele (R13, Crm::Entrega::Dono). Sem memória entre chamadas: a nova tentativa depois de o
  # agente de IA recusar (#concluir_para_ia!) decide de novo.
  def fila(card, settings)
    @dono.fila(Crm::Entrega::QuemCuida.new(conversation: @conversation, card: card).pessoas, regra: settings)
  end

  def nada(motivo) = Plano.new(acao: :nada, motivo: motivo)

  # O card do assunto em atendimento, relido aqui, sob a trava (#1606, regra única Crm::Assunto.funil_atual). O card que
  # a IA do CRM passou é o da avaliação; se o assunto mudou desde então, vale o atual (corrida c). Sem olhar a chave do
  # CRM: o card aberto que existe já decide quem vê a conversa (Crm::Access::Recipients), e a fila usa o mesmo funil.
  # `pelo_card` (#1693): o card do pedido, enquanto seguir aberto nesta conversa, em foco ou não.
  def card_em_atendimento
    atual = Crm::Assunto.funil_atual(@conversation)
    @assunto_mudou = @card.present? && atual&.id != @card.id
    self.class.card_da_regra(@conversation, card: @card, pelo_card: @pelo_card, atual: atual)
  end

  # O robô que estava com a conversa antes desta entrega: o valor do banco, porque na passagem do robô
  # (ConversationBotHandoff#bot_handoff!) ele já saiu da memória. Lido uma vez: a entrega que roda de novo sem IA
  # (concluir_para_ia!) relê a conversa, e o robô já não está mais nela.
  def robo_que_atendia
    return unless @conversation.attribute_in_database('ai_assignee_type') == 'AgentBot'

    AgentBot.find_by(id: @conversation.attribute_in_database('assignee_agent_bot_id'))
  end

  def regra_do(card)
    return if card.blank?

    settings = Crm::Ai::Config.handoff_settings(card.stage, card.pipeline)
    settings if settings[:enabled]
  end

  def executar(plano, gravar:)
    case plano.acao
    when :pessoa then entregar(plano, gravar)
    when :segurar then segurar(plano, gravar)
    when :convite then convidar(plano, gravar)
    when :ia then Resultado.new(status: :para_ia, agente: plano.agente, card: plano.card)
    else resultado(:nada, plano)
    end
  end

  # O porquê da passagem é anotado ANTES de gravar: a conversa o prende no save que troca a pessoa.
  def entregar(plano, gravar)
    anotar_passagem(plano)
    return resultado(:nada, nada('falhou_atribuir')) unless atribuir(plano.pessoa, gravar)

    registro(plano)&.entregue!(plano.pessoa, razao: @razao)
    resultado(:entregue, plano)
  end

  # Uma gravação só (Crm::Entrega::Atribuicao): revalida a pessoa na conta, cala o robô e encerra as esperas.
  def atribuir(pessoa, gravar)
    return false unless Crm::Entrega::Atribuicao.aplicar(@conversation, pessoa)

    @conversation.save! if gravar
    true
  end

  # A marca guarda a origem (@motivo), a falha (por que ainda não entregou) e o motivo da IA do CRM (@razao, #1975: a
  # entrega pela fila leva o porquê ao card). Convite que nunca sai, passado o prazo do
  # convite: segue segura, com a falha "nao_conseguimos_chamar" e um aviso (Crm::Entrega::AvisoSemNinguem).
  def segurar(plano, gravar)
    vencido = Crm::Entrega::AvisoSemNinguem.vencido?(@conversation, plano)
    falha = vencido ? Crm::Entrega::AvisoSemNinguem::FALHA : plano.motivo
    Marca.marcar(@conversation, modo: Marca::SEGURANDO, motivo: @motivo, falha: falha, sugestao: @sugestao, dono: @dono.dirigido,
                                card: (plano.card if @pelo_card), razao: @razao)
    Crm::Entrega::AvisoSemNinguem.new(conversation: @conversation, card: plano.card).avisar! if vencido
    @conversation.save! if gravar && @conversation.changed?
    Resultado.new(status: :segurando, motivo: falha, card: plano.card)
  end

  # Convite: participante + notificação, sem atribuir e sem calar o robô. O ciclo é gravado sob a trava do card, que
  # relê o intervalo: duas passagens ao mesmo tempo não convidam duas vezes.
  def convidar(plano, gravar)
    falha = convite_no_card(plano)
    # Convite que não saiu (ninguém recebe a notificação, ou um convite recente ainda vale): segura com a marca, para o
    # rodízio nativo não passar por cima e a fila tentar de novo.
    return segurar(Plano.new(acao: :segurar, card: plano.card, settings: plano.settings, motivo: falha), gravar) if falha

    convite_como_passagem!(plano)
    ate = Time.current + plano.settings[:invite_ttl_seconds].to_i.seconds
    Marca.marcar(@conversation, modo: Marca::CONVITE, motivo: @motivo, ate: ate, convidado: plano.pessoa, card: (plano.card if @pelo_card))
    @conversation.save! if gravar && @conversation.changed?
    resultado(:convidado, plano)
  end

  # Savepoint próprio: o rollback de um convite que ninguém recebe desfaz só o convite, não a trava de quem chamou.
  def convite_no_card(plano)
    falha = 'convite_falhou'
    plano.card.with_lock(requires_new: true) do
      if convite_no_intervalo?(plano)
        falha = 'intervalo'
        next
      end
      raise ActiveRecord::Rollback unless Crm::Ai::HandoffInviter.new(conversation: @conversation, agent: plano.pessoa, idempotente: true).perform

      registro(plano).convidado!(plano.pessoa, razao: @razao)
      falha = nil
    end
    falha
  end

  # A entrega para uma pessoa vira passagem pelo escritor único (Crm::PassagensListener, depois do commit): aqui só o
  # porquê vai junto, no contexto do Crm::Passagens.com_motivo aberto pelo #call ou pela passagem do robô
  # (ConversationBotHandoff#bot_handoff!). Quem pediu: o robô, quando foi ele (pediu a passagem, ou o agente externo pelo
  # toggle); senão a pessoa logada ou o sistema (a IA do CRM, a triagem, o robô desligado).
  def anotar_passagem(plano)
    Crm::Passagens.anotar(card: plano.card, pedida_por: PEDIDO_DO_ROBO.include?(@motivo) ? @quem_atendia : nil)
  end

  # O convite não atribui (o listener não vê troca): é a única passagem para pessoa gravada aqui (#1606, aprovado pelo
  # Multifunnel). Savepoint próprio: se o registro falhar, o convite segue, e a falha fica no log, com ids.
  def convite_como_passagem!(plano)
    pediu = PEDIDO_DO_ROBO.include?(@motivo) ? @quem_atendia : nil
    Crm::Passagens.registrar!(conversation: @conversation, de: @quem_atendia, para: plano.pessoa, pedida_por: pediu,
                              motivo: Crm::Passagens::CONVITE, card: plano.card)
  rescue ActiveRecord::ActiveRecordError, ArgumentError => e
    Rails.logger.error("[crm][passagem] nao_registrada evento=convite conversa=#{@conversation.id} erro=#{e.class}")
  end

  # Passagem recente demais para convidar de novo (Crm::Entrega::RegistroNoCard#intervalo_ativo?).
  def convite_no_intervalo?(plano) = registro(plano).intervalo_ativo?

  def registro(plano)
    return if plano.card.blank? || plano.settings.blank?

    Crm::Entrega::RegistroNoCard.new(card: plano.card, conversation: @conversation, settings: plano.settings)
  end

  def resultado(status, plano)
    Resultado.new(status: status, pessoa: plano.pessoa, motivo: plano.motivo, card: plano.card)
  end

  # Toda saída deixa uma linha, só com ids e rótulos de lista fechada (nunca texto do cliente ou do modelo).
  def registrar
    Rails.logger.info(
      "[crm][entrega] conversa=#{@conversation.id} conta=#{@conversation.account_id} card=#{@resultado.card&.id || '-'} " \
      "motivo=#{@motivo} origem=#{@origem} desfecho=#{@resultado.status} pessoa=#{@resultado.pessoa&.id || '-'} " \
      "detalhe=#{@resultado.motivo || '-'}#{' assunto_mudou' if @assunto_mudou}"
    )
  end
end
