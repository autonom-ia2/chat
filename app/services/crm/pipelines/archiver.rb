# Arquivar um funil (#2095), com a opção de levar antes os cards abertos para uma etapa de outro funil ativo, as caixas
# para outro funil ativo e de passar o "principal" para outro funil. O arquivamento vai numa transação: se algo falhar,
# o funil, as caixas e o principal não mudam.
#
# Mover (#2145): num lote só, o card de cada cliente ficava travado até o fim (1.000 cards seguravam 2,3 s a 3,6 s quem
# fosse criar ou mexer em card desses clientes). Com mais de LOTE cards abertos, os ids deles são lidos uma vez, no
# começo, e vão em lotes de LOTE, cada um na sua transação; a transação final leva o último lote, o que nasceu ou voltou
# ao funil no meio, e arquiva. Até LOTE cards, tudo vai na transação final, como antes. Ler os ids uma vez é o que faz o
# laço terminar: dois arquivamentos cruzados (P1 para P2 e P2 para P1) não ficam devolvendo cards um ao outro.
# Cada lote confere de novo, sob as travas, o que a transação final confere (o funil não mudou de status desde o
# começo, o novo principal, a regra do único principal, o destino dos cards e o das caixas): o que seria recusado no
# fim é recusado antes do lote. Se um lote for recusado no meio (o destino arquivado, ou este funil arquivado por outro
# pedido, entre dois lotes), os lotes já levados ficam no destino e o funil continua como estava, com o resto; a recusa
# leva quantos foram (`moved_before_failure`, que o controller devolve como `moved_count`). Se o destino foi arquivado
# no meio, os levados seguem a escolha daquele arquivamento (no cruzado P1 para P2 e P2 para P1, podem ter voltado à
# origem): a contagem é de quantos saíram, não de onde estão agora. Arquivar de novo leva o que sobrou.
# Cliente que já tinha card aberto no funil de destino (#2145, decisão do Rodrigo, opção 1): o card movido vai mesmo
# assim. O PLANO do multifunil (R1) aceita vários cards abertos do mesmo cliente no mesmo funil. O resultado lista esses
# clientes (`clientes_com_dois_abertos`), para o resumo dizer "N clientes ficaram com mais de um card aberto em <funil>".
#
# Entre os lotes, as caixas ainda apontam para este funil: o cliente sem card aberto que escrever nesse meio ganha card
# aqui, e ele vai no último lote.
#
# Sem destino, os cards abertos ficam no funil arquivado e voltam ao quadro quando ele for restaurado
# (Api::V1::Accounts::Crm::PipelinesController#restore). Com `stop_follow_ups` ("Guardar junto" da janela nova, decisão
# 2), os retornos marcados deles param (Crm::Pipelines::RetornosDosGuardados); sem ele, arquiva como antes, sem mexer
# neles (a janela antiga, com a flag crm_arquivados desligada, não avisa que parariam). Fechados e arquivados ficam sempre.
#
# Caixas (decisão 7): com `inboxes_target`, as ligações caixa↔funil (Crm::PipelineInbox) vão para o funil de destino.
# Se o destino já tem a mesma caixa, fica a ligação dele, com `auto_create_card` ligado se qualquer uma das duas criava.
# O funil padrão da caixa (Crm::InboxSetting#default_pipeline_id) que apontava para o arquivado passa ao destino, na
# primeira etapa dele. Isso é tudo o que faz a caixa criar card no funil (Crm::Conversations::CardSyncer e
# Crm::Cards::ConversationDefaultsResolver). Sem `inboxes_target`, as ligações ficam: o CardSyncer só usa funil ativo,
# então a caixa para de criar card neste funil e volta a criar quando ele for restaurado.
#
# `new_default`: outro funil ativo vira o principal (e este deixa de ser), antes da regra do único principal.
#
# Travas, nesta ordem:
# 1. a de arquivar da conta, a mesma do PATCH de status (Crm::Pipelines::TravaDeArquivar): dois arquivamentos ao mesmo
#    tempo se enfileiram, então não zeram os funis ativos nem se cruzam. Não é a linha da conta: ver o arquivo dela;
# 2. o funil, relido (FOR NO KEY UPDATE: não barra o INSERT de card ou etapa que aponta para ele, que pega FOR KEY
#    SHARE); o novo principal, relido e promovido; e então a regra do último funil ativo e do único principal
#    (Crm::Pipeline#motivo_para_nao_arquivar) vale para o estado de agora;
# 3. a etapa de destino (FOR SHARE: não pode ser apagada no meio, e o card que entra nela continua entrando) e o funil
#    dela, e o funil de destino das caixas, relidos: o destino arquivado, ou a etapa apagada, entre a escolha na tela e
#    este momento é recusado, sem prender os cards de novo;
# 4. os cards abertos que vão mudar (ou, no "Guardar junto", as séries, os lembretes e os cards que ficam), e as
#    ligações das caixas.
# Um card que outro pedido cria neste funil enquanto o arquivamento roda (a caixa escolheu o funil antes de ele ficar
# arquivado) fica aberto no funil arquivado e volta quando ele for restaurado, como os que a pessoa escolheu guardar.
#
# O card movido muda de funil pelo modelo (Crm::Card#update!), para valer o que a troca de funil dispara: a contagem do
# acesso por funil, o agente de IA responsável da caixa e a sugestão de repasse. A atividade 'move' de cada um sai em
# lote e leva `motivo: 'funil_arquivado'`, sem webhook nem conversão de anúncio e sem as automações das etapas: é a
# conta reorganizando funis, não o cliente avançando (o mesmo critério da etapa apagada, Crm::PipelineStages::Destroyer).
# O card cujo dono já saiu da conta vai sem dono (Crm::Card.donos_fora_da_conta): o modelo recusaria gravá-lo com ele.
class Crm::Pipelines::Archiver
  INVALID_TARGET = 'crm.pipeline_archive_invalid_target'.freeze
  INVALID_INBOXES_TARGET = 'crm.pipeline_archive_invalid_inboxes_target'.freeze
  INVALID_DEFAULT = 'crm.pipeline_archive_invalid_new_default'.freeze
  MOTIVO = 'funil_arquivado'.freeze
  # Linha do funil e dos cards que vão mudar: muda coluna comum, não a chave (ver as travas acima).
  TRAVA_DO_FUNIL = 'FOR NO KEY UPDATE'.freeze
  # O que o update! do card valida e lê: pré-carregado uma vez para o lote, não uma consulta por card.
  CARD_PRELOAD = %i[contact inbox team primary_conversation owner].freeze
  # Cards por transação ao mover (#2145): ~0,3 s de trava por lote, pela medida da revisão do #2097.
  LOTE = 100

  Result = Struct.new(:moved, :stopped_follow_ups, :moved_inboxes, :inboxes_target_pipeline_id, :clientes_com_dois_abertos,
                      keyword_init: true)

  # Outro pedido arquivou ou restaurou este funil enquanto os lotes saíam: as escolhas eram para o funil de antes.
  CHANGED = 'crm.pipeline_archive_changed'.freeze

  # O destino não serve; a mensagem é o código da recusa (INVALID_TARGET, INVALID_INBOXES_TARGET, INVALID_DEFAULT ou
  # CHANGED).
  class InvalidTarget < StandardError; end

  # A regra do último funil ativo ou do único principal recusou (Crm::Pipeline#motivo_para_nao_arquivar).
  class Blocked < StandardError
    attr_reader :motivo

    def initialize(motivo)
      @motivo = motivo
      super("crm.pipeline_archive_#{motivo}")
    end
  end

  ESCOLHAS = %i[target_stage inboxes_target new_default stop_follow_ups].freeze

  # escolhas: target_stage, inboxes_target e new_default já vêm resolvidos entre os que a pessoa enxerga (o controller
  # confere); precisam ser de outro funil ativo da mesma conta, e são conferidos de novo sob a trava. stop_follow_ups:
  # true no "Guardar junto".
  def initialize(pipeline:, actor:, **escolhas)
    escolhas.assert_valid_keys(*ESCOLHAS)
    @pipeline = pipeline
    @actor = actor
    @target_stage = escolhas[:target_stage]
    @inboxes_target = escolhas[:inboxes_target]
    @new_default = escolhas[:new_default]
    @stop_follow_ups = escolhas[:stop_follow_ups] == true
    @status_inicial = pipeline.status
    @moved_before_failure = 0
  end

  # Quantos cards os lotes já confirmados levaram, quando o arquivamento é recusado ou falha depois deles.
  attr_reader :moved_before_failure

  def perform
    result = arquivar!
    Result.new(**result.to_h, clientes_com_dois_abertos: resumo_dos_dois_abertos(result.moved))
  end

  private

  def arquivar!
    movidos = @target_stage ? mover_em_lotes! : []
    result = nil
    ActiveRecord::Base.transaction do
      travar_funil!
      recusar_se_o_funil_mudou!
      promote_new_default!
      motivo = @pipeline.motivo_para_nao_arquivar
      raise Blocked, motivo if motivo

      result = archive!
    end
    avisar_movidos(result.moved)
    Result.new(**result.to_h, moved: movidos + result.moved)
  rescue StandardError
    # Falhou na transação final: os lotes já tinham saído (se falhou num lote, mover_em_lotes! já contou).
    @moved_before_failure = movidos.size if movidos
    raise
  end

  def travar_funil!
    Crm::Pipelines::TravaDeArquivar.travar!(@pipeline.account_id)
    @pipeline.lock!(TRAVA_DO_FUNIL)
  end

  # Os lotes antes da transação final (ver o cabeçalho), dos ids lidos uma vez; o último lote fica para ela.
  def mover_em_lotes!
    lotes = @pipeline.cards.open.order(:id).pluck(:id).each_slice(LOTE).to_a
    lotes[0...-1].each_with_object([]) do |ids, movidos|
      lote = ActiveRecord::Base.transaction do
        travar_funil!
        move_open_cards!(conferir_escolhas!, ids: ids)
      end
      movidos.concat(lote)
      @moved_before_failure = movidos.size
      avisar_movidos(lote)
    end
  end

  def recusar_se_o_funil_mudou!
    raise InvalidTarget, CHANGED if @pipeline.status != @status_inicial
  end

  # O que a transação final confere, sem mexer em nada e na mesma ordem de travas dela (novo principal, destino dos
  # cards, destino das caixas): o lote só sai se o fim não fosse recusar. A regra do funil
  # (Crm::Pipeline#motivo_para_nao_arquivar) com o novo principal, quando veio, já resolvendo o "único principal"; o
  # "último funil ativo" não acontece com destino, que é de outro funil ativo. Devolve a etapa de destino.
  def conferir_escolhas!
    recusar_se_o_funil_mudou!
    lock_active_other!(@new_default.id, INVALID_DEFAULT) if @new_default
    motivo = @pipeline.motivo_para_nao_arquivar
    raise Blocked, motivo if motivo && !(motivo == 'only_default' && @new_default)

    target = lock_target!
    lock_active_other!(@inboxes_target.id, INVALID_INBOXES_TARGET) if @inboxes_target
    target
  end

  # O arquivamento já está confirmado: se a leitura do resumo falhar, ele sai sem a lista (com o erro no log), em vez de
  # a resposta virar erro.
  def resumo_dos_dois_abertos(movidos)
    clientes_com_dois_abertos(movidos)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("[crm][pipelines][archiver] pipeline_id=#{@pipeline.id} resumo_dois_abertos #{e.class.name}: #{e.message.to_s[0, 160]}")
    []
  end

  # Lido depois de confirmar, só para o resumo: os clientes dos cards movidos que já tinham outro card aberto no funil
  # de destino (um card que não veio deste funil). Um por cliente, com o card movido.
  def clientes_com_dois_abertos(movidos)
    contatos = movidos.filter_map(&:contact_id).uniq
    return [] if contatos.empty?

    ja_abertos = contatos_ja_abertos_no_destino(contatos, movidos.map(&:id))
    movidos.select { |card| ja_abertos.include?(card.contact_id) }.uniq(&:contact_id).map { |card| cliente_do_resumo(card) }
  end

  def contatos_ja_abertos_no_destino(contatos, movidos_ids)
    Crm::Card.open.where(account_id: @pipeline.account_id, pipeline_id: @target_stage.pipeline_id, contact_id: contatos)
             .where.not(id: movidos_ids).distinct.pluck(:contact_id).to_set
  end

  def cliente_do_resumo(card) = { contact_id: card.contact_id, name: card.contact&.name, card_id: card.id }

  def avisar_movidos(cards) = cards.each { |card| Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_MOVED) }

  def archive!
    target = lock_target!
    inboxes_target = @inboxes_target && lock_active_other!(@inboxes_target.id, INVALID_INBOXES_TARGET)
    moved = target ? move_open_cards!(target) : []
    moved_inboxes = inboxes_target ? move_inboxes!(inboxes_target) : []
    stopped = parar_retornos_dos_guardados!(target)
    @pipeline.archived! unless @pipeline.archived?
    Result.new(moved: moved, stopped_follow_ups: stopped, moved_inboxes: moved_inboxes, inboxes_target_pipeline_id: inboxes_target&.id)
  end

  # "Guardar junto" (sem destino e com stop_follow_ups): os retornos dos cards que ficam param. Devolve quantos.
  def parar_retornos_dos_guardados!(target)
    return 0 if target || !@stop_follow_ups

    Crm::Pipelines::RetornosDosGuardados.new(@pipeline).parar!
  end

  def promote_new_default!
    return if @new_default.nil?

    pipeline = lock_active_other!(@new_default.id, INVALID_DEFAULT)
    pipeline.update!(is_default: true) unless pipeline.is_default?
    @pipeline.update!(is_default: false) if @pipeline.is_default?
  end

  def lock_target!
    return if @target_stage.nil?

    stage = Crm::PipelineStage.lock('FOR SHARE').find_by(id: @target_stage.id, account_id: @pipeline.account_id)
    raise InvalidTarget, INVALID_TARGET if stage.nil?

    lock_active_other!(stage.pipeline_id, INVALID_TARGET)
    stage
  end

  # Outro funil ativo da mesma conta, relido sob a trava.
  def lock_active_other!(pipeline_id, code)
    pipeline = Crm::Pipeline.lock(TRAVA_DO_FUNIL).find_by(id: pipeline_id, account_id: @pipeline.account_id)
    raise InvalidTarget, code unless pipeline&.active? && pipeline.id != @pipeline.id

    pipeline
  end

  # ids: o lote; sem ele, todos os abertos (a transação final).
  def move_open_cards!(target, ids: nil)
    now = Time.current
    @stage_names = nil
    abertos = @pipeline.cards.open
    abertos = abertos.where(id: ids) if ids
    cards = abertos.order(:id).lock(TRAVA_DO_FUNIL).includes(*CARD_PRELOAD).to_a
    sem_dono = Crm::Card.donos_fora_da_conta(@pipeline.account_id, cards.map(&:owner_id))
    cards.each do |card|
      attributes = { pipeline: target.pipeline, stage: target, entered_stage_at: now, last_activity_at: now }
      attributes[:owner_id] = nil if sem_dono.include?(card.owner_id)
      card.update!(attributes)
    end
    # rubocop:disable Rails/SkipsModelValidations
    Crm::Activity.insert_all!(cards.map { |card| move_activity(card, target, now) }) if cards.any?
    # rubocop:enable Rails/SkipsModelValidations
    cards
  end

  # As ligações das caixas vão para o destino. A etapa padrão da ligação era deste funil: no destino, fica vazia (o card
  # nasce na primeira etapa, Crm::Conversations::CardSyncer#default_stage_for).
  def move_inboxes!(target)
    links = @pipeline.pipeline_inboxes.where.not(inbox_id: nil).order(:id).lock.includes(:inbox).to_a
    kept = target.pipeline_inboxes.where(inbox_id: links.map(&:inbox_id)).lock.index_by(&:inbox_id)
    links.each { |link| move_inbox_link!(link, kept[link.inbox_id], target) }
    move_inbox_settings!(target)
    links.map { |link| { id: link.inbox_id, name: link.inbox&.name } }
  end

  # Sem ligação da mesma caixa no destino, a ligação muda de funil. Com ela, fica a do destino, criando card se
  # qualquer uma das duas criava, e a deste funil sai.
  def move_inbox_link!(link, existing, target)
    return link.update!(pipeline: target, default_stage: nil) if existing.nil?

    existing.update!(auto_create_card: true) if link.auto_create_card? && !existing.auto_create_card?
    link.destroy!
  end

  def move_inbox_settings!(target)
    first_stage = target.stages.order(:position, :id).first
    @pipeline.account.crm_inbox_settings.where(default_pipeline_id: @pipeline.id).order(:id).lock.each do |setting|
      setting.update!(default_pipeline: target, default_stage: first_stage)
    end
  end

  def move_activity(card, target, now)
    {
      account_id: @pipeline.account_id, card_id: card.id, actor_type: @actor ? @actor.class.name.underscore : 'system',
      actor_id: @actor&.id, event_type: 'move', created_at: now,
      payload: { from_pipeline_id: @pipeline.id, to_pipeline_id: target.pipeline_id,
                 from_stage_id: card.stage_id_before_last_save, to_stage_id: target.id,
                 from_stage_name: stage_names[card.stage_id_before_last_save], to_stage_name: target.name,
                 motivo: MOTIVO }.merge(dono_que_saiu(card))
    }
  end

  # O dono que saiu da conta e foi tirado do card na mudança, para o histórico dizer por quê.
  def dono_que_saiu(card)
    return {} unless card.saved_change_to_owner_id?

    { dono_que_saiu_id: card.owner_id_before_last_save }
  end

  def stage_names
    @stage_names ||= @pipeline.stages.pluck(:id, :name).to_h
  end
end
