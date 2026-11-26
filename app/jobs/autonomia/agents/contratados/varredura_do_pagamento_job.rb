# A VARREDURA DO PAGAMENTO DO SEGURO VIAGEM (#3246b), a cada 5 minutos (config/schedule.yml). Acha as propostas que ainda
# esperam pagamento, reserva cada uma e enfileira uma conferência (`ConferirPagamentoJob`) por proposta. A Bia avisa
# sozinha quando o pagamento cai, e lembra uma vez antes de o link vencer.
#
# ELEGÍVEL: proposta com carrinho, cotação criada há menos de 2 dias, `gerada_em` entre 24 h 10 min e 5 min atrás, sem
# `pago_em`, sem `voucher_enviado_em`, `situacao` diferente de cancelado e `conferido_em` vazio ou de mais de 9 min 30 s
# atrás (uma conferência a cada duas rodadas, no máximo). Lote de 200.
#
# DUAS ETAPAS, POR CAUSA DO `gerada_em` MALFORMADO. Ele é texto dentro do jsonb, e o cast `::timestamptz` de um valor
# inválido derruba a consulta inteira (e com ela a varredura de todas as contas). Sem migration, não há função segura de
# conversão; `pg_input_is_valid` só existe a partir do Postgres 16, e o `AND` não garante a ordem da avaliação. Então:
#   1. uma seleção AMPLA, sem cast nenhum (as condições que não dependem do `gerada_em`), lê id e `gerada_em` como texto;
#      a tabela é pequena e o `created_at` de 2 dias a limita;
#   2. o Ruby lê o `gerada_em` (`Time.zone.iso8601`; o inválido fica de fora, com log) e aplica a janela;
#   3. a RESERVA, no molde da varredura da Automação: `UPDATE … WHERE id IN (SELECT … FOR UPDATE SKIP LOCKED)
#      RETURNING`, que grava `conferido_em` e confere de novo as condições, inclusive o espaçamento. O `conferido_em` é
#      escrito só aqui, sempre em UTC no mesmo formato (`iso8601`), e por isso a comparação como texto é a comparação do
#      tempo, sem cast. Duas varreduras ao mesmo tempo não reservam a mesma linha: a segunda pula a travada, ou já a
#      encontra com o `conferido_em` novo.
class Autonomia::Agents::Contratados::VarreduraDoPagamentoJob < ApplicationJob
  queue_as :scheduled_jobs

  LOTE = 200
  CRIADA_HA_MENOS_DE = 2.days
  PRIMEIRA_CONFERENCIA = 5.minutes
  ULTIMA_CONFERENCIA = 24.hours + 10.minutes
  ESPACO_ENTRE_CONFERENCIAS = 9.minutes + 30.seconds
  EventoDaViagem = ::Autonomia::Agents::Tools::EventoDaViagem

  # As condições da seleção e da reserva, sem cast: chaves ausentes ou vazias, texto contra texto (o `conferido_em` com a
  # collation "C", byte a byte, para a ordem do texto ser a do tempo em qualquer collation do banco).
  CONDICOES = <<~SQL.squish.freeze
    proposta IS NOT NULL AND created_at > :desde
      AND proposta->>'codigo_carrinho' IS NOT NULL AND proposta->>'gerada_em' IS NOT NULL
      AND COALESCE(proposta->>'pago_em', '') = '' AND COALESCE(proposta->>'voucher_enviado_em', '') = ''
      AND proposta->>'situacao' IS DISTINCT FROM 'cancelado'
      AND (COALESCE(proposta->>'conferido_em', '') = '' OR (proposta->>'conferido_em') COLLATE "C" < :espaco)
  SQL

  def perform
    agora = Time.current.utc
    reservar(candidatas(agora), agora).each { |id, gerada_em| enfileirar(id, EventoDaViagem.gerada_em_i('gerada_em' => gerada_em)) }
  end

  private

  def cotacoes = ::Autonomia::Agents::CotacaoDeViagem

  def parametros(agora)
    { desde: agora - CRIADA_HA_MENOS_DE, espaco: (agora - ESPACO_ENTRE_CONFERENCIAS).iso8601 }
  end

  # -> os ids na janela do `gerada_em`, até o lote. O `gerada_em` que não é ISO 8601 fica de fora (log com o id).
  def candidatas(agora)
    janela = (agora - ULTIMA_CONFERENCIA)..(agora - PRIMEIRA_CONFERENCIA)
    linhas = cotacoes.where(CONDICOES, parametros(agora)).order(:id).pluck(:id, Arel.sql("proposta->>'gerada_em'"))
    linhas.filter_map do |id, texto|
      gerada_em = EventoDaViagem.gerada_em('gerada_em' => texto)
      Rails.logger.warn("[autonomia][pagamento_automatico] gerada_em_invalida cotacao=#{id}") if gerada_em.nil?
      id if gerada_em && janela.cover?(gerada_em)
    end.first(LOTE)
  end

  # -> [[id, gerada_em], …] reservados agora, com `agora` em `conferido_em`.
  def reservar(ids, agora)
    return [] if ids.empty?

    sql = cotacoes.sanitize_sql_array([<<~SQL.squish, parametros(agora).merge(ids: ids, agora: agora.iso8601, lote: LOTE)])
      UPDATE autonomia_cotacoes_de_viagem
      SET proposta = proposta || jsonb_build_object('conferido_em', CAST(:agora AS text))
      WHERE id IN (SELECT id FROM autonomia_cotacoes_de_viagem
                   WHERE id IN (:ids) AND #{CONDICOES}
                   ORDER BY id LIMIT :lote FOR UPDATE SKIP LOCKED)
      RETURNING id, proposta->>'gerada_em'
    SQL
    cotacoes.connection.select_rows(sql).map { |id, gerada_em| [id.to_i, gerada_em] }
  end

  # Sem rescue: a fila fora derruba esta rodada (fica no log do Sidekiq), e as linhas já reservadas voltam depois do
  # espaçamento, como qualquer outra.
  def enfileirar(id, gerada_em_i)
    ::Autonomia::Agents::Contratados::ConferirPagamentoJob.perform_later(id, gerada_em_i)
  end
end
