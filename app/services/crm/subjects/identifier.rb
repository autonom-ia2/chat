# Decide o assunto de uma mensagem recebida (#1145) e aplica conforme o modo da caixa. Ver Crm::Subjects.
#
# Uma decisão por mensagem: a linha é reservada (pending) antes de perguntar, e o índice único (conversa, mensagem)
# impede que um retry do job pergunte e aplique de novo. A pergunta leva segundos (Jev e, às vezes, o modelo maior);
# quem aplica confere de novo dentro do lock da conversa (Crm::Subjects::Applier).
#
# Vários assuntos numa mensagem (#1693, flag `crm_avaliar_toda_mensagem`): o Jev ganha a opção "vários assuntos", e o
# modelo maior devolve a lista (um principal e os outros). Continua UMA decisão por mensagem: ela guarda o principal
# (card_id, action, title) e a lista dos cards tocados (touched_card_ids), que a IA do CRM avalia numa chamada só
# (Crm::Conversations::CardsTocados). Com a flag, um assunto só também grava a lista.
#
# Coluna do card novo (#1910, flag `crm_assunto_na_etapa`): o modelo maior devolve também a etapa de cada pedido novo
# (Crm::Subjects::Etapa), que vai na Escolha até o Applier.
#
# Dúvida com sinal de pedido novo (#2162, flag `crm_ia_duvida_vira_sugestao`, Crm::Subjects::DuvidaSugerida): a dúvida
# em que o Jev ou o modelo maior viu um pedido novo vira sugestão de criar o card, que a equipe aceita ou ignora.
class Crm::Subjects::Identifier # rubocop:disable Metrics/ClassLength -- passou do teto (175) com o motivo da revisão (#2018), que mora junto dos gatilhos
  # outros (#1693): os outros assuntos da mensagem, cada um uma Escolha sem decided_by. duvida: os atributos da decisão
  # quando o principal ficou em dúvida e os outros, claros, seguem (sem opcao). etapa (#1910): a chave da etapa do pedido
  # novo, ou nil (1ª etapa).
  # generico (#2163): o modelo disse que o nome é genérico.
  Escolha = Struct.new(:opcao, :titulo, :decided_by, :outros, :duvida, :etapa, :generico, keyword_init: true)
  LEITURAS = %w[mensagens_com_respostas].freeze
  SEM_MUDANCA = (Crm::Subjects::Applier::SEM_EFEITO + %w[kept doubt superseded]).freeze

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @account = conversation.account
  end

  def perform
    setting = Crm::InboxSetting.find_by(account_id: @account.id, inbox_id: @conversation.inbox_id, crm_enabled: true)
    return unless perguntar?(setting)

    anterior = existente
    return anterior if pipelines.empty?

    @mode = setting.subject_ai_mode
    @decisao = anterior ? reabrir(anterior) : reservar
    return existente if @decisao.nil?

    decidir
    avisar
    @decisao
  end

  private

  # #2084: contato marcado parceiro ou não é negócio não passa pela IA de assunto: nem card, nem sugestão, nem
  # pergunta ao modelo. O IdentifyJob segue e grava o marco que o ReplyJob espera.
  def perguntar?(setting)
    return false if setting.nil? || setting.subject_ai_off? || !Crm::Ai::Config.enabled?

    !Crm::Relacao.fora_do_funil?(@conversation.contact)
  end

  def existente = Crm::SubjectDecision.find_by(conversation_id: @conversation.id, message_id: @message.id)

  # Mensagem já decidida só volta a ser perguntada quando o Híbrido recuperou o texto real (#1638). O retrato é a
  # decisão de antes: volta se der erro, e diz ao Applier qual card a IA já tinha nomeado.
  def reabrir(anterior)
    @retrato = Crm::Subjects::Reabertura.reabrir(anterior, @message, @mode)
    anterior.reload if @retrato
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
  # card. Decisão reaberta (#1638) nunca é apagada: volta ao que era antes.
  def desfazer_reserva(erro)
    Rails.logger.error("[crm][assunto] decisão #{@decisao.id} falhou: #{erro.class}")
    falha = { state: 'failed', reason: erro.class.name.first(120), **medicao }
    return @decisao.update_columns(falha) if @aplicado # rubocop:disable Rails/SkipsModelValidations

    @retrato ? @decisao.update_columns(@retrato) : @decisao.destroy # rubocop:disable Rails/SkipsModelValidations
  end

  def perguntar
    @jev = TypesafeAi::Decisor.new(feature: Crm::Subjects::FEATURE).decidir(decisor: question, estado: estado)
    opcao = question.opcao(@jev.resposta)
    @opcao_do_jev = opcao
    @jev_answer = opcao.tipo.to_s
    repetida = sugestao_repetida(opcao)
    return concluir(state: 'kept', **alvo(opcao), reason: repetida, **tocados_da_repetida(opcao)) if repetida

    @review_reason = motivo_da_revisao(opcao)
    escolha = @review_reason ? revisar : Escolha.new(opcao: opcao, decided_by: 'jev')
    return if escolha.nil?

    resultado = aplicar(escolha)
    @aplicado = gravou?(escolha, resultado)
    @evento = resultado.delete(:evento)
    tocados = lista_de_tocados(resultado)
    concluir(**resultado, decided_by: escolha.decided_by, **tocados)
  end

  # A dúvida que não virou nada (#2162) não gravou card nem sugestão: um erro depois dela desfaz a reserva, como antes.
  def gravou?(escolha, resultado)
    !(escolha.opcao.nil? && escolha.outros.blank? && resultado[:state] == 'doubt')
  end

  # A lista de cards tocados (#1693), tirada do resultado. Dúvida sem nenhum outro assunto aplicado fica sem lista: a
  # IA do CRM relê o card em foco (#1675).
  def lista_de_tocados(resultado)
    tocados = resultado.delete(:tocados)
    return {} if tocados.nil? || (resultado[:state] == 'doubt' && tocados.empty?)

    { touched_card_ids: tocados.map(&:id) }
  end

  def aplicar(escolha)
    applier = Crm::Subjects::Applier.new(conversation: @conversation, question: question, mode: @mode, decisao: @decisao,
                                         anterior: @retrato)
    unless question.varios?
      # A dúvida que virou sugestão (#2162) não tem opção aplicada: só a dúvida, com a sugestão dentro.
      return applier.duvida(escolha.duvida) if escolha.opcao.nil?

      return applier.aplicar(escolha.opcao, escolha.titulo, escolha.etapa, generico: escolha.generico == true)
    end

    applier.aplicar_varios((escolha if escolha.opcao), Array(escolha.outros), duvida: escolha.duvida)
  end

  # A mesma sugestão já espera uma pessoa (#1693): o card de volta ainda é o assunto da mensagem; o pedido novo não
  # tem card. Sem a flag, nada (a IA do CRM relê o card em foco, como antes).
  def tocados_da_repetida(opcao)
    return {} unless question.varios?

    { touched_card_ids: opcao.tipo == :card ? [opcao.card.id] : [] }
  end

  # O aviso em tempo real sai com a decisão já gravada: falhar aqui não desfaz nem repete nada.
  def avisar
    return if mesmo_resultado?

    Crm::Cards::Broadcaster.broadcast(@decisao.card, @evento) if @evento && @decisao.card
    Crm::Subjects::Notifier.notify(@conversation) if %w[applied suggested].include?(@decisao&.state)
    avaliar_card_novo
  end

  # Reaberta que chegou ao mesmo resultado de antes (#1638): a tela já mostra isso, nada a avisar. Voltar a um assunto
  # só é igual se ele já era o atual antes desta decisão (a pessoa pode ter trocado o foco no meio-tempo).
  def mesmo_resultado?
    campos = %w[state action card_id title]
    return false unless @retrato.present? && @decisao.attributes.slice(*campos) == @retrato.slice(*campos)

    @decisao.action != 'focus' || question.atual&.id == @decisao.card_id
  end

  # Card novo do pedido é o assunto atual: a IA avalia ele, não o anterior (#1147). A troca de foco agenda em Focus.
  # Com a lista de cards tocados (#1693), a avaliação conjunta (Crm::Conversations::CardsTocados) deixa esta velha; se
  # ela falhar, esta segue valendo.
  def avaliar_card_novo
    return unless @decisao&.state == 'applied' && @decisao.action == 'create'

    Crm::Ai::Observer.new(card: @decisao.card).schedule_evaluation
  end

  # Jev inseguro, pedido novo (precisa de nome) ou vários assuntos (precisa da lista): o modelo maior decide. Inseguro
  # também, nada muda. "O mesmo assunto" num card ainda sem nome (#1918) também, quando dar nome a ele é possível. E
  # "o mesmo assunto" num card de nome genérico (#2163): o modelo maior diz se o detalhe chegou e qual o nome.
  # Devolve o motivo, gravado na decisão para medir o revisor (#2018), ou nil (o Jev decide sozinho). Com mais de um
  # valendo, fica o primeiro desta ordem; só a certeza baixa soma com outro.
  def motivo_da_revisao(opcao)
    return 'certeza_baixa' if @jev.certeza < Crm::Subjects::CERTEZA_MINIMA
    return 'pedido_novo' if opcao.tipo == :novo
    return 'varios' if opcao.tipo == :varios
    return 'nome_do_atual' if nome_do_atual?(opcao)

    'nome_provisorio' if nome_provisorio?(opcao)
  end

  # #2163: o modelo maior diz se o detalhe chegou, até TENTATIVAS vezes por card (o custo não cresce sem fim quando o
  # detalhe nunca chega).
  def nome_provisorio?(opcao)
    opcao.tipo == :mesmo && question.atual_nomeavel? && Crm::Subjects::NomeProvisorio.tentativa_livre?(question.atual, @conversation)
  end

  # O Jev sozinho não deixa o primeiro pedido sem nome (#1918): quem escolhe entre continuar o card sem nome e dar nome
  # a ele (o pedido novo no funil dele) é o modelo maior. Só quando essa opção existe e não é a sugestão que já espera
  # uma pessoa ou que ela dispensou (#1260); senão vale a certeza do Jev.
  def nome_do_atual?(opcao) = opcao.tipo == :mesmo && question.nome_do_atual.present? && sugestao_repetida(question.nome_do_atual).nil?

  # A mesma sugestão já espera uma pessoa, ou ela acabou de dispensá-la (#1260): nada a fazer, sem pagar o modelo maior.
  # Vale por RESPEITO_AO_FECHAMENTO: depois disso a IA pode sugerir de novo, e uma sugestão esquecida não prende a
  # conversa para sempre.
  def sugestao_repetida(opcao)
    decisoes = mesma_sugestao(opcao)
    return 'sugestao_pendente' if decisoes.exists?(state: 'suggested')

    'sugestao_dispensada' if decisoes.exists?(state: 'dismissed')
  end

  # Pedido novo num funil vira card novo ou nome do atual sem nome; voltar a um assunto é foco naquele card.
  def mesma_sugestao(opcao)
    return Crm::SubjectDecision.none unless %i[novo card].include?(opcao.tipo)

    recentes = Crm::SubjectDecision.where(conversation_id: @conversation.id)
                                   .where(updated_at: Crm::Subjects::RESPEITO_AO_FECHAMENTO.ago..)
    return recentes.where(action: 'focus', card_id: opcao.card.id) if opcao.tipo == :card

    recentes.where(action: %w[create rename], pipeline_id: opcao.pipeline.id)
  end

  def alvo(opcao)
    opcao.tipo == :novo ? { action: 'create', pipeline_id: opcao.pipeline.id } : { action: 'focus', card_id: opcao.card.id }
  end

  def revisar
    veredito = Crm::Subjects::Reviewer.new(question).revisar(estado, @jev)
    opcao = question.opcao(veredito.resposta)
    duvida = !veredito.seguro || (opcao.tipo == :novo && veredito.titulo.blank?)
    outros = outros(veredito)
    unless duvida
      return Escolha.new(opcao: opcao, titulo: veredito.titulo, decided_by: 'review', outros: outros, etapa: veredito.etapa,
                         generico: veredito.generico)
    end

    em_duvida = em_duvida(opcao, veredito)
    # O principal em dúvida não segura os outros assuntos, claros, da mesma mensagem (#1693, C27). A dúvida com sinal de
    # pedido novo (#2162) vai ao Applier, que a sugere dentro da trava.
    return Escolha.new(decided_by: 'review', outros: outros, duvida: em_duvida) if outros.any? || em_duvida.key?(:sugestao)

    concluir(**em_duvida, decided_by: 'review')
    nil
  end

  # Os atributos da decisão em dúvida, com a sugestão de pedido novo quando há sinal (#2162).
  def em_duvida(opcao, veredito)
    { state: 'doubt', action: 'none', title: veredito.titulo.presence, pipeline: opcao.pipeline, reason: veredito.motivo,
      **sugestao_da_duvida(opcao, veredito) }
  end

  # #2162: o sinal de pedido novo na dúvida, pela resposta do modelo maior ou, sem ela, pela do Jev. O funil e o nome do
  # modelo maior valem primeiro; o do Jev vem sem nome. Sem sinal, ou com a mesma sugestão esperando ou ignorada (#1260),
  # nada (a dúvida fica como antes).
  def sugestao_da_duvida(opcao, veredito)
    return {} unless Crm::Subjects::DuvidaSugerida.ligada?(@account)

    novo = [opcao, @opcao_do_jev].find { |candidata| candidata&.tipo == :novo }
    return {} if novo.nil? || sugestao_repetida(novo)

    { sugestao: { pipeline: novo.pipeline, title: (veredito.titulo.presence if novo == opcao) } }
  end

  # Os outros assuntos da lista (#1693), sem o principal: o mesmo assunto repetido sai (o card aberto, ou o pedido novo
  # com o mesmo funil e o mesmo nome), pedido novo sem nome sai, assunto em dúvida sai (nada muda nele), e a lista
  # inteira respeita MAX_ASSUNTOS.
  def outros(veredito)
    return [] if veredito.assuntos.blank?

    vistos = [identidade(veredito.assuntos[veredito.principal])]
    escolhas = veredito.assuntos.filter_map do |assunto|
      identidade = identidade(assunto)
      next if !assunto.seguro || vistos.include?(identidade) || (identidade.is_a?(Array) && assunto.titulo.blank?)

      vistos << identidade
      escolha_de(assunto)
    end
    escolhas.first(Crm::Subjects::MAX_ASSUNTOS - 1)
  end

  def escolha_de(assunto)
    Escolha.new(opcao: question.opcao(assunto.resposta), titulo: assunto.titulo, etapa: assunto.etapa, generico: assunto.generico)
  end

  # O card do assunto aberto, ou [funil, nome] do pedido novo.
  def identidade(assunto)
    opcao = question.opcao(assunto.resposta)
    opcao.tipo == :novo ? [opcao.chave, assunto.titulo] : opcao.card.id
  end

  # Assunto encerrado (IA entende a conversa F2): com a flag, os cards fechados há pouco da mesma leitura viram opção
  # (Crm::Subjects::Encerrado.da_conversa), de qualquer funil: escolhê-los não mexe em card nenhum.
  def question
    @question ||= begin
      todos = Crm::Cards::ConversationCardFinder.new(account: @account).all(@conversation).includes(:pipeline, :stage, :contact).to_a
      abertos = todos.select(&:open?)
      # Voltar a um assunto só entre os funis com a IA ligada (#1260); o atual segue sendo o atual, de qualquer funil.
      ids = pipelines.map(&:id)
      cards = abertos.select { |card| ids.include?(card.pipeline_id) }
      # O card da chegada intocado não é "o mesmo assunto" (#1918, só com vários assuntos).
      chegada = varios? && Crm::Subjects::CardDaChegada.intacta?(conversation: @conversation, card: abertos.first, mode: @mode)
      Crm::Subjects::Question.new(account: @account, pipelines: pipelines, cards: cards, atual: abertos.first, varios: varios?,
                                  etapas: etapas?, chegada: chegada, encerrados: Crm::Subjects::Encerrado.da_conversa(@account, todos),
                                  automatica: @mode == 'auto')
    end
  end

  # Vários assuntos só com a flag e numa decisão nova: a reaberta pelo Híbrido (#1638) segue de um assunto só.
  def varios?
    @retrato.nil? && Crm::Conversations::CardEmFoco.ligada?(@account)
  end

  # A coluna do card novo (#1910) só na Automática: no Sugerir o card aceito nasce na 1ª etapa, e a pergunta fica a de
  # sempre. A decisão reaberta pelo Híbrido (#1638) segue sem coluna, como segue de um assunto só.
  def etapas?
    @retrato.nil? && @mode == 'auto' && Crm::Subjects::Etapa.ligada?(@account)
  end

  # IA entende a conversa F1: com a flag, a conversa vai com a hora e o papel de quem falou (Crm::Subjects.janela).
  def estado
    @estado ||= Autonomia::Decisores::Estado.new(conversation: @conversation, message: @message, leituras: LEITURAS, **Crm::Subjects.janela(@account))
  end

  # Os funis ativos ligados à caixa da conversa, com etapa para o card nascer e a IA do funil ligada, na ordem do CRM.
  def pipelines
    @pipelines ||= @account.crm_pipelines.active.joins(:pipeline_inboxes, :stages)
                           .where(crm_pipeline_inboxes: { inbox_id: @conversation.inbox_id })
                           .order(:position, :id).distinct.to_a
                           .select { |pipeline| Crm::Subjects.ia_do_funil?(pipeline) }
  end

  def cota_esgotada?
    Crm::SubjectDecision.where(account_id: @account.id, created_at: Time.current.all_month)
                        .where.not(decided_by: nil).count >= Crm::Subjects::LIMITE_MENSAL
  end

  # Reaberta (#1638) que não mudou nada (sem cota, Jev fora, nada para ler, dúvida, mantido, repetido ou vencido por
  # uma mais nova) volta ao que era: o que valia antes continua valendo, e o card do aviso fica como estava. Com o
  # horário de agora: já leu o texto real e não reabre outra vez.
  def concluir(**atributos)
    if @retrato && SEM_MUDANCA.include?(atributos[:state])
      return @decisao.update_columns(@retrato.merge('updated_at' => Time.current)) # rubocop:disable Rails/SkipsModelValidations
    end

    padrao = { confidence: @jev&.certeza, decided_by: ('jev' if @jev), **medicao }
    @decisao.update!(padrao.merge(atributos))
  end

  # O que o Jev respondeu e por que o modelo maior foi chamado (#2018): só registro, para medir o revisor. Nulos antes de
  # o Jev responder; review_reason também quando ele decide sozinho.
  def medicao
    { jev_answer: @jev_answer, review_reason: @review_reason }
  end
end
