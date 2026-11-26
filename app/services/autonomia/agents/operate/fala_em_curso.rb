# QUEM ESTÁ FALANDO E QUANDO TERMINA (#3211). É o par do fluxo externo "fim previsto da fala" + "agente ocupado", em duas
# chaves do Redis por conversa:
#
# - `fala_em_curso` (CHAVE_OCUPADA): o id da mensagem do cliente cujo turno está falando (IA ou pedaços). Serve à fila
#   (P2): o turno novo só segue quando a marca some ou deixa de ser de outro turno.
# - `fim_da_fala` (CHAVE_DO_FIM): o instante previsto em que a fala termina, com o turno que o gravou
#   ("<id da mensagem do cliente>:<ms epoch>"). Serve à espera da rajada (P1). #3235: o fim é a soma das esperas reais
#   da cadeia agendada (`duracao_da_cadeia_ms`, os mesmos `delay_ms` que o ChunkedDeliveryJob usa), não uma estimativa
#   pelo tamanho do texto: ~650 caracteres previam ~104 s para uma entrega de 38 s, e a rajada seguinte esperava à toa.
#   E a cadeia apaga o fim do seu turno quando a fala acaba (`esquecer_o_fim`): no último pedaço e em qualquer parada.
#
# Por que não reaproveita o TurnoEmCurso: aquela marca é aberta a cada mensagem do cliente e a mais nova toma; esta é do
# turno que está falando, e só ele a solta. As duas convivem.
#
# `ocupar`/`renovar`/`soltar` seguem o molde do TurnoEmCurso (TTL = teto do turno; renovar e soltar só do próprio turno,
# com WATCH/MULTI). O TTL é rede de segurança: o caminho normal sempre solta.
#
# Nunca levanta por falha do Redis: é sinal de cortesia. Redis fora do ar quer dizer "ninguém ocupando, sem fim
# previsto", e o agente responde com a espera mínima. Só o erro do Redis é engolido (Redis::BaseError e o tempo de espera
# do pool, ConnectionPool::TimeoutError: o `soltar` roda no ensure de todo ReplyJob e ChunkedDeliveryJob, mesmo com as
# opções desligadas); erro de código sobe, para não virar "ninguém falando" em silêncio.
module Autonomia::Agents::Operate::FalaEmCurso
  CHAVE_OCUPADA = 'autonomia:fala_em_curso:%<conversa>d'.freeze
  CHAVE_DO_FIM = 'autonomia:fim_da_fala:%<conversa>d'.freeze
  # Valores do fluxo externo: teto de 150 s, validade de 2,5 h.
  TETO_DO_FIM_MS = 150_000
  TTL_DO_FIM = 9000
  # A espera antes de cada pedaço, presa entre 0,1 s e 30 s: a mesma do agendamento (Responder e ChunkedDeliveryJob).
  ESPERA_MINIMA_DO_PEDACO = 0.1
  ESPERA_MAXIMA_DO_PEDACO = 30.0

  module_function

  def chave_ocupada(conversation_id) = format(CHAVE_OCUPADA, conversa: conversation_id)

  def chave_do_fim(conversation_id) = format(CHAVE_DO_FIM, conversa: conversation_id)

  # `agent`: o teto do turno é o dele (TurnoEmCurso.teto_do_turno), que com a paridade cobre a espera e a fila.
  def ocupar(conversation_id, message_id, agent = nil)
    ::Redis::Alfred.set(chave_ocupada(conversation_id), message_id.to_s, ex: ::Autonomia::Agents::Operate::TurnoEmCurso.teto_do_turno(agent).to_i)
    nil
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    nil
  end

  # -> true quando renovou (a marca era deste turno).
  def renovar(conversation_id, message_id)
    chave = chave_ocupada(conversation_id)
    ttl = ::Autonomia::Agents::Operate::TurnoEmCurso::TTL_DA_CADEIA.to_i
    ::Redis::Alfred.with do |redis|
      redis.watch(chave) do
        next redis.unwatch && false unless redis.get(chave) == message_id.to_s

        Array(redis.multi { |transacao| transacao.expire(chave, ttl) }).first.present?
      end
    end
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    false
  end

  def soltar(conversation_id, message_id)
    return if message_id.blank?

    ::Redis::Alfred.delete_if_equals(chave_ocupada(conversation_id), message_id.to_s)
    nil
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    nil
  end

  # Há marca e ela é de outro turno que não o `message_id`. Sem marca: false.
  def ocupada_por_outro?(conversation_id, message_id)
    dono = ::Redis::Alfred.get(chave_ocupada(conversation_id))
    dono.present? && dono != message_id.to_s
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    false
  end

  # O id da mensagem do cliente cujo turno está falando (String), ou nil sem marca (#3225: a fila sabe se a fala é de um
  # turno anterior à mensagem que espera).
  def dono(conversation_id)
    ::Redis::Alfred.get(chave_ocupada(conversation_id)).presence
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    nil
  end

  # Segundos de espera antes do pedaço (`delay_ms`, já com o RitmoDoCanal), presos como o agendamento os prende. Uma
  # regra só para quem agenda o pedaço e para a duração da fala (#3235).
  def espera_do_pedaco(chunk)
    (chunk['delay_ms'].to_i / 1000.0).clamp(ESPERA_MINIMA_DO_PEDACO, ESPERA_MAXIMA_DO_PEDACO)
  end

  # Quanto a cadeia de pedaços leva para sair inteira: a soma das esperas de todos os pedaços, em ms (#3235).
  def duracao_da_cadeia_ms(chunks)
    (Array(chunks).sum { |chunk| espera_do_pedaco(chunk) } * 1000).round
  end

  # Grava o fim previsto da fala do turno `message_id` ("<message_id>:<ms epoch>"): agora mais `duracao_ms`, a duração
  # real da entrega (duracao_da_cadeia_ms; 0 para a resposta que sai inteira na hora), com teto. -> o instante gravado,
  # ou nil se o Redis falhou.
  def prever_fim!(conversation_id, message_id, duracao_ms, agora: Time.current)
    fim = agora + ([duracao_ms.to_i, TETO_DO_FIM_MS].min / 1000.0)
    ::Redis::Alfred.set(chave_do_fim(conversation_id), "#{message_id}:#{(fim.to_f * 1000).round}", ex: TTL_DO_FIM)
    fim
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    nil
  end

  # -> Time ou nil. Só o que vem depois do último ":" é o instante (método de string, sem regex).
  def fim_previsto(conversation_id)
    ms = ::Redis::Alfred.get(chave_do_fim(conversation_id)).to_s.split(':').last
    return if ms.blank?

    Time.zone.at(ms.to_i / 1000.0)
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    nil
  end

  # Apaga o fim previsto só se ele é do turno `message_id` (compare-and-delete, WATCH/MULTI): o fim de um turno mais novo
  # fica. -> true quando apagou.
  def esquecer_o_fim(conversation_id, message_id)
    return false if message_id.blank?

    chave = chave_do_fim(conversation_id)
    ::Redis::Alfred.with do |redis|
      redis.watch(chave) do
        next redis.unwatch && false unless redis.get(chave).to_s.split(':').first == message_id.to_s

        Array(redis.multi { |transacao| transacao.del(chave) }).first.to_i.positive?
      end
    end
  rescue ::Redis::BaseError, ::ConnectionPool::TimeoutError
    false
  end
end
