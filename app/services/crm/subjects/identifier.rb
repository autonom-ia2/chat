# Decide o assunto de uma mensagem recebida (#1145) e aplica conforme o modo da caixa. Ver Crm::Subjects.
#
# Uma decisão por mensagem: a linha é reservada (pending) antes de perguntar, e o índice único (conversa, mensagem)
# impede que um retry do job pergunte e aplique de novo. A pergunta leva segundos (Jev e, às vezes, o modelo maior);
# quem aplica confere de novo dentro do lock da conversa (Crm::Subjects::Applier).
class Crm::Subjects::Identifier
  Escolha = Struct.new(:opcao, :titulo, :decided_by, keyword_init: true)
  LEITURAS = %w[mensagens_com_respostas].freeze

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @account = conversation.account
  end

  def perform
    setting = Crm::InboxSetting.find_by(account_id: @account.id, inbox_id: @conversation.inbox_id, crm_enabled: true)
    return if setting.nil? || setting.subject_ai_off?
    return existente if existente || pipelines.empty?

    @mode = setting.subject_ai_mode
    @decisao = reservar
    return existente if @decisao.nil?

    decidir
    avisar
    @decisao
  end

  private

  def existente
    Crm::SubjectDecision.find_by(conversation_id: @conversation.id, message_id: @message.id)
  end

  # Outro job da mesma mensagem reservou primeiro: nil, e quem chamou devolve a linha dele.
  def reservar
    Crm::SubjectDecision.create!(account: @account, conversation: @conversation, message: @message, mode: @mode,
                                 action: 'none', state: 'pending')
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Mensagem só de áudio ou imagem no fim de uma rajada também conta: o Estado lê as últimas mensagens com texto.
  def decidir
    return concluir(state: 'no_content') if estado.vazio?
    return concluir(state: 'no_quota') if cota_esgotada?
    return concluir(state: 'failed', reason: 'jev_nao_configurado') unless TypesafeAi::Config.configured?

    perguntar
  rescue TypesafeAi::Decisor::Error, Crm::Subjects::Reviewer::Error => e
    concluir(state: 'failed', reason: e.message.to_s.first(120))
  rescue StandardError => e
    desfazer_reserva(e)
    raise
  end

  # Erro inesperado (banco, card apagado no meio): antes de aplicar, a transação do lock já voltou atrás, então a
  # reserva sai e o retry do job pergunta de novo. Depois de aplicar, a decisão fica como falha: repetir criaria outro
  # card.
  def desfazer_reserva(erro)
    Rails.logger.error("[crm][assunto] decisão #{@decisao.id} falhou: #{erro.class}")
    @aplicado ? @decisao.update_columns(state: 'failed', reason: erro.class.name.first(120)) : @decisao.destroy # rubocop:disable Rails/SkipsModelValidations
  end

  def perguntar
    @jev = TypesafeAi::Decisor.new(feature: Crm::Subjects::FEATURE).decidir(decisor: question, estado: estado)
    opcao = question.opcao(@jev.resposta)
    return concluir(state: 'kept', action: 'create', pipeline: opcao.pipeline, reason: 'sugestao_pendente') if ja_sugerido?(opcao)

    escolha = revisar?(opcao) ? revisar : Escolha.new(opcao: opcao, decided_by: 'jev')
    return if escolha.nil?

    resultado = Crm::Subjects::Applier.new(conversation: @conversation, question: question, mode: @mode, decisao: @decisao)
                                      .aplicar(escolha.opcao, escolha.titulo)
    @aplicado = true
    @evento = resultado.delete(:evento)
    concluir(**resultado, decided_by: escolha.decided_by)
  end

  # O aviso em tempo real sai com a decisão já gravada: falhar aqui não desfaz nem repete nada.
  def avisar
    Crm::Cards::Broadcaster.broadcast(@decisao.card, @evento) if @evento && @decisao.card
    Crm::Subjects::Notifier.notify(@conversation) if %w[applied suggested].include?(@decisao&.state)
  end

  # Jev inseguro, ou pedido novo (precisa de nome): o modelo maior decide. Inseguro também, nada muda.
  def revisar?(opcao)
    @jev.certeza < Crm::Subjects::CERTEZA_MINIMA || opcao.tipo == :novo
  end

  # Modo Sugerir: o pedido novo naquele funil já espera uma pessoa. Não paga o modelo maior de novo a cada mensagem.
  def ja_sugerido?(opcao)
    @mode == 'suggest' && opcao.tipo == :novo &&
      Crm::SubjectDecision.suggested.exists?(conversation_id: @conversation.id, pipeline_id: opcao.pipeline.id)
  end

  def revisar
    veredito = Crm::Subjects::Reviewer.new(question).revisar(estado, @jev)
    opcao = question.opcao(veredito.resposta)
    duvida = !veredito.seguro || (opcao.tipo == :novo && veredito.titulo.blank?)
    return Escolha.new(opcao: opcao, titulo: veredito.titulo, decided_by: 'review') unless duvida

    concluir(state: 'doubt', decided_by: 'review', title: veredito.titulo.presence, pipeline: opcao.pipeline,
             reason: veredito.motivo)
    nil
  end

  def question
    @question ||= begin
      cards = Crm::Cards::ConversationCardFinder.new(account: @account).all(@conversation).includes(:pipeline, :contact).to_a.select(&:open?)
      Crm::Subjects::Question.new(account: @account, pipelines: pipelines, cards: cards, atual: cards.first)
    end
  end

  def estado
    @estado ||= Autonomia::Decisores::Estado.new(conversation: @conversation, message: @message, leituras: LEITURAS)
  end

  # Os funis ativos ligados à caixa da conversa, com etapa para o card nascer, na ordem do CRM.
  def pipelines
    @pipelines ||= @account.crm_pipelines.active.joins(:pipeline_inboxes, :stages)
                           .where(crm_pipeline_inboxes: { inbox_id: @conversation.inbox_id })
                           .order(:position, :id).distinct.to_a
  end

  def cota_esgotada?
    Crm::SubjectDecision.where(account_id: @account.id, created_at: Time.current.all_month)
                        .where.not(decided_by: nil).count >= Crm::Subjects::LIMITE_MENSAL
  end

  def concluir(**atributos)
    padrao = { confidence: @jev&.certeza, decided_by: ('jev' if @jev) }
    @decisao.update!(padrao.merge(atributos))
  end
end
