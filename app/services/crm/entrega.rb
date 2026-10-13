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
class Crm::Entrega
  Resultado = Struct.new(:status, :pessoa, :motivo, :card, keyword_init: true)
  Plano = Struct.new(:acao, :pessoa, :card, :settings, :motivo, keyword_init: true)

  # `pedido`: o que a IA do CRM pediu, quando é ela que chama (`sugestao`: o nome que ela sugeriu, para a regra
  # "direto"; `razao`: o motivo dela, para a linha do tempo do card).
  def initialize(conversation:, motivo:, origem:, card: nil, pedido: {})
    @conversation = conversation
    @motivo = motivo.to_s
    @origem = origem.to_s
    @card = card
    @sugestao = pedido[:sugestao]
    @razao = pedido[:razao]
  end

  # Por conta própria: trava a conversa, relê e grava.
  def call
    @conversation.with_lock { @resultado = executar(planejar, gravar: true) }
    registrar
    @resultado
  end

  # Dentro de ConversationBotHandoff#bot_handoff!, com a linha já travada: a passagem grava status, robô e pessoa numa
  # gravação só (os callbacks veem a troca de status e a de atendente juntas). Aqui a conversa muda só na memória.
  def na_passagem
    @resultado = executar(planejar, gravar: false)
    registrar
    @resultado
  end

  private

  def planejar
    return nada('ja_tem_pessoa') if @conversation.assignee_id.present?
    return nada('fechada') unless @conversation.open? || @conversation.pending?

    card = card_em_atendimento
    settings = regra_do(card)
    settings ? pela_regra(card, settings) : sem_regra(card)
  end

  def pela_regra(card, settings)
    convite = settings[:handoff_mode] == 'r3_invite'
    selector = seletor(card, settings, require_online: convite ? false : settings[:prefer_online])
    escolher(selector, card, settings, acao: convite ? :convite : :pessoa)
  end

  # Sem regra: quem cuida da conversa e está online, com menos conversas abertas (decisão 2 do Rodrigo, 13/10).
  def sem_regra(card)
    selector = Crm::Ai::HandoffMemberSelector.new(
      inbox: @conversation.inbox, account_id: @conversation.account_id, members: fila(card),
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

  def seletor(card, settings, require_online:)
    Crm::Ai::HandoffMemberSelector.new(
      inbox: @conversation.inbox, account_id: @conversation.account_id, members: fila(card),
      mode: settings[:selector_mode], prefer_online: settings[:prefer_online], require_online: require_online,
      suggested_name: @sugestao, pool_type: settings[:pool_type], pool_id: settings[:pool_id], conversation: @conversation
    )
  end

  def fila(card)
    @fila ||= Crm::Entrega::QuemCuida.new(conversation: @conversation, card: card).pessoas
  end

  def nada(motivo)
    Plano.new(acao: :nada, motivo: motivo)
  end

  # O card do assunto em atendimento (#1141). Quem já tem o card (a IA do CRM) o passa. Sem olhar a chave do CRM: o
  # card aberto que existe já decide quem vê a conversa (Crm::Access::Recipients), e a fila tem de usar o mesmo funil.
  def card_em_atendimento
    return @card if @card

    card = Crm::Cards::ConversationCardFinder.new(account: @conversation.account).find(@conversation)
    card if card&.open?
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
    else resultado(:nada, plano)
    end
  end

  def entregar(plano, gravar)
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

  # A marca guarda a origem (@motivo) e a falha (por que ainda não entregou). Convite que nunca sai, passado o prazo do
  # convite: segue segura, com a falha "nao_conseguimos_chamar" e um aviso (Crm::Entrega::AvisoSemNinguem).
  def segurar(plano, gravar)
    vencido = Crm::Entrega::AvisoSemNinguem.vencido?(@conversation, plano)
    falha = vencido ? Crm::Entrega::AvisoSemNinguem::FALHA : plano.motivo
    Crm::Entrega::Marca.marcar(@conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: @motivo, falha: falha, sugestao: @sugestao)
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

    ate = Time.current + plano.settings[:invite_ttl_seconds].to_i.seconds
    Crm::Entrega::Marca.marcar(@conversation, modo: Crm::Entrega::Marca::CONVITE, motivo: @motivo, ate: ate)
    @conversation.save! if gravar && @conversation.changed?
    resultado(:convidado, plano)
  end

  # Savepoint próprio: o rollback de um convite que ninguém recebe desfaz só o convite, não a trava de quem chamou.
  def convite_no_card(plano)
    falha = 'convite_falhou'
    plano.card.with_lock(requires_new: true) do
      registro = registro(plano)
      if registro.intervalo_ativo?
        falha = 'intervalo'
        next
      end
      raise ActiveRecord::Rollback unless Crm::Ai::HandoffInviter.new(conversation: @conversation, agent: plano.pessoa, idempotente: true).perform

      registro.convidado!(plano.pessoa, razao: @razao)
      falha = nil
    end
    falha
  end

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
      "detalhe=#{@resultado.motivo || '-'}"
    )
  end
end
