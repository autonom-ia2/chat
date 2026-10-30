# Os retornos marcados dos cards abertos que ficam num funil arquivado (#2095, "Guardar junto"). O funil some do quadro,
# e um retorno que sai dele mandaria mensagem ao cliente de um card que ninguém vê. Ao arquivar, eles param: os lembretes,
# tarefas e follow-ups ainda por vencer são cancelados (motivo `pipeline_archived`) e as séries que repetem encerram. Se
# o funil for restaurado, não voltam sozinhos (a tela avisa e oferece "Agendar retorno").
#
# A reunião marcada NÃO para, como no arquivar do card (Crm::Cards::Archiver): cancelar avisa o cliente, e isso é decisão
# de quem atende. Ela e o lembrete dela ficam, e a prévia conta quantas são.
#
# A cadência do follow-up de IA dos cards que ficam também para (Crm::Cards::Archiver.metadata_sem_cadencia, sem gastar):
# sem isto o estado ficava `active: true` e o planner, ao restaurar o funil, tratava o card como em cadência para sempre.
#
# Travas e passagens como no arquivar do card (Crm::Cards::Archiver), na ordem do resto do CRM: séries, lembretes, cards.
# 1. Esperando: as séries e os lembretes ativos dos cards abertos, depois os cards.
# 2. Com os cards travados, sem esperar (SKIP LOCKED): o que nasceu entre uma coisa e outra (criar série ou lembrete do
#    card segura o card até terminar, então já terminou). O que estiver travado por outro (DueProcessor,
#    SeriesMaterializer) não é esperado e fica de fora: nada espera depois dos cards, então não há ciclo.
class Crm::Pipelines::RetornosDosGuardados
  MOTIVO = 'pipeline_archived'.freeze

  def initialize(pipeline)
    @pipeline = pipeline
  end

  # O que a prévia do arquivamento mostra.
  def contagem
    {
      follow_ups_count: lembretes.count,
      follow_up_series_count: series.count,
      upcoming_meetings_count: reunioes.count
    }
  end

  # Devolve quantos lembretes foram cancelados (as séries encerradas não entram: a vez seguinte de cada uma é um lembrete).
  def parar!(now: Time.current)
    travadas, cancelados, cards = travar!
    travadas.each { |serie| serie.update!(status: :ended, ended_at: now) }
    cancelados.each do |lembrete|
      lembrete.update!(status: :canceled, canceled_at: now, metadata: lembrete.metadata.to_h.merge('canceled_reason' => MOTIVO))
    end
    parar_cadencias!(cards)
    atualizar_proximo_retorno(cancelados)
    cancelados.size
  end

  private

  # As duas passagens (ver o topo do arquivo). Devolve [séries, lembretes, cards].
  def travar!
    travadas = series.order(:id).lock.to_a
    cancelados = lembretes.order(:id).lock.to_a
    cards = @pipeline.cards.open.order(:id).lock(Crm::Pipelines::Archiver::TRAVA_DO_FUNIL).to_a
    [travadas + sem_esperar(series, travadas), cancelados + sem_esperar(lembretes, cancelados), cards]
  end

  def sem_esperar(relacao, vistos)
    relacao.where.not(id: vistos.map(&:id)).order(:id).lock('FOR UPDATE SKIP LOCKED').to_a
  end

  def parar_cadencias!(cards)
    cards.each do |card|
      metadata = Crm::Cards::Archiver.metadata_sem_cadencia(card, motivo: MOTIVO, gasta: false)
      card.update!(metadata: metadata) unless metadata.equal?(card.metadata)
    end
  end

  def card_ids
    @pipeline.cards.open.select(:id)
  end

  def series
    Crm::FollowUpSeries.where(account_id: @pipeline.account_id, card_id: card_ids, status: %i[active paused])
  end

  def lembretes
    lembretes_das_reunioes = reunioes.where.not(reminder_id: nil).select(:reminder_id)
    Crm::FollowUp.active.where(account_id: @pipeline.account_id, card_id: card_ids).where.not(id: lembretes_das_reunioes)
  end

  def reunioes
    Crm::Meeting.where(account_id: @pipeline.account_id, card_id: card_ids).upcoming
  end

  def atualizar_proximo_retorno(cancelados)
    Crm::Card.where(id: cancelados.map(&:card_id).uniq).find_each { |card| Crm::FollowUps::CardNextDueUpdater.update(card) }
  end
end
