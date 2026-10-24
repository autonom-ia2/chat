# Arquivar um card, o mesmo caminho para a pessoa (Api::V1::Accounts::Crm::CardsController#destroy), o lote
# (Crm::Cards::BulkAction) e a IA (Crm::Ai::NaoENegocio e o aceite do "era teste", Crm::Ai::FecharCard::Aceite).
#
# Arquivado, o card não tem mais o que fazer: as sugestões de etapa da IA pendentes expiram; os lembretes, tarefas e
# follow-ups ainda por vencer são cancelados (motivo `card_archived`, o mesmo que o DueProcessor usa); e o lembrete que
# repete deixa de repetir. O card ganho ou perdido continua nos Números (Crm::Card::DESFECHO_ARQUIVADO).
#
# A reunião marcada com o cliente NÃO é cancelada: cancelar avisa o cliente (convite do calendário ou WhatsApp), e isso
# é decisão de quem atende, pela tela da reunião. Ela fica, com o lembrete dela, e a atividade do arquivamento registra
# quais ficaram (`reunioes_mantidas`).
#
# Ordem das travas, a do resto do CRM: série, lembrete, card. O SeriesMaterializer trava a série antes de criar a vez; o
# DueProcessor trava o lembrete e só no fim o card (a chamada lenta à IA ou o envio acontecem com o lembrete travado e o
# card livre, Crm::FollowUps::AutoFollowupRunner); o cancelamento de reunião e o reset do follow-up da IA também. Por
# isso o card não vem primeiro aqui. O card é relido sob a trava: o status de agora decide o desfecho guardado.
#
# Duas passagens, e a segunda nunca espera:
# 1. Antes do card, trava (esperando) as séries e os lembretes ativos.
# 2. Com o card travado, pega o que nasceu entre uma coisa e outra (criar série ou lembrete do card segura o card até
#    terminar, então já terminou) com SKIP LOCKED. O que estiver travado por outro é do DueProcessor ou do
#    SeriesMaterializer, que leem o status do card na barreira (Crm::Cards::Archiver.arquivado_sob_trava?), esperam este arquivamento e
#    o encontram arquivado: cancelam o lembrete ou encerram a série. Nada espera depois do card, então não há ciclo.
class Crm::Cards::Archiver
  MOTIVO = 'card_archived'.freeze

  def initialize(card:, actor:, payload: {})
    @card = card
    @actor = actor
    @payload = payload.to_h
    @now = Time.current
  end

  # true quando arquivou; false quando o card já estava arquivado (nada muda, nada é registrado). O bloco, quando há,
  # roda sob as travas, com o card relido, e decide se ainda arquiva (as guardas da IA); false desiste sem arquivar.
  def perform
    ActiveRecord::Base.transaction do
      series = travar_series
      lembretes = travar_lembretes
      @card.lock!
      next false if (block_given? && !yield) || @card.archived?

      arquivar!(series + series_novas(series), lembretes + lembretes_novos(lembretes))
      true
    end
  end

  # A barreira de quem age sobre um lembrete ou série do card (DueProcessor, SeriesMaterializer), já com a trava deles:
  # FOR KEY SHARE espera um arquivamento em curso (o card FOR UPDATE) e, lido aberto, segura até o fim da transação de
  # quem leu, então o arquivamento espera por ela. Não bloqueia o UPDATE comum do card (FOR NO KEY UPDATE).
  def self.arquivado_sob_trava?(card_id)
    Crm::Card.where(id: card_id).lock('FOR KEY SHARE').pick(:status) == 'archived'
  end

  # A cadência do follow-up de IA acaba com o card arquivado (as tarefas dela foram canceladas): sem isto o estado
  # ficava `active: true` e o planner tratava o card como em cadência. Terminal, como o fechamento no Runner.
  # `gasta: false` (funil arquivado com o card dentro, Crm::Pipelines::RetornosDosGuardados): para sem gastar, e o
  # planner volta a armar quando o funil for restaurado (ele só varre funil ativo).
  def self.metadata_sem_cadencia(card, motivo: MOTIVO, gasta: true)
    estado = card.metadata.to_h.dig('ai', 'auto_followup_state').to_h
    return card.metadata unless estado['active'] == true

    fim = estado.merge('active' => false, 'stopped_reason' => motivo, 'next_due_at' => nil)
    fim['spent'] = true if gasta
    card.metadata.to_h.deep_merge('ai' => { 'auto_followup_state' => fim })
  end

  private

  def series_ativas
    Crm::FollowUpSeries.where(account_id: @card.account_id, card_id: @card.id, status: %i[active paused]).order(:id)
  end

  def travar_series = series_ativas.lock.to_a

  def travar_lembretes = @card.follow_ups.active.order(:id).lock.to_a

  def series_novas(vistas) = series_ativas.where.not(id: vistas.map(&:id)).lock('FOR UPDATE SKIP LOCKED').to_a

  def lembretes_novos(vistos) = @card.follow_ups.active.where.not(id: vistos.map(&:id)).order(:id).lock('FOR UPDATE SKIP LOCKED').to_a

  # A série encerra antes de as vezes serem canceladas: nenhuma vez nova nasce depois do cancelamento.
  def arquivar!(series, lembretes)
    @card.update!(status: :archived, last_activity_at: @now, metadata: self.class.metadata_sem_cadencia(@card))
    expirar_sugestoes!
    encerrar_series!(series)
    da_reuniao = reunioes_mantidas.filter_map(&:reminder_id)
    cancelados = lembretes.reject { |lembrete| da_reuniao.include?(lembrete.id) }
    cancelar_lembretes!(cancelados)
    Crm::FollowUps::CardNextDueUpdater.update(@card)
    Crm::ActivityLogger.new(card: @card, actor: @actor, event_type: 'archive', payload: registro(cancelados.size)).perform
  end

  def expirar_sugestoes!
    @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).find_each { |sugestao| sugestao.update!(status: :expired) }
  end

  def encerrar_series!(series)
    series.each { |serie| serie.update!(status: :ended, ended_at: @now) }
  end

  def cancelar_lembretes!(lembretes)
    lembretes.each do |lembrete|
      lembrete.update!(status: :canceled, canceled_at: @now, metadata: lembrete.metadata.to_h.merge('canceled_reason' => MOTIVO))
    end
  end

  # Lidas com o card travado, depois de todas as travas.
  def reunioes_mantidas
    @reunioes_mantidas ||= Crm::Meeting.where(account_id: @card.account_id, card_id: @card.id).upcoming.to_a
  end

  def registro(cancelados)
    extra = {}
    extra[:lembretes_cancelados] = cancelados if cancelados.positive?
    extra[:reunioes_mantidas] = reunioes_mantidas.map(&:id) if reunioes_mantidas.any?
    @payload.merge(extra)
  end
end
