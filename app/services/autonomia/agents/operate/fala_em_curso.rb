# QUEM ESTÁ FALANDO E QUANDO TERMINA (#3211). É o par do fluxo externo "fim previsto da fala" + "agente ocupado", em duas
# chaves do Redis por conversa:
#
# - `fala_em_curso` (CHAVE_OCUPADA): o id da mensagem do cliente cujo turno está falando (IA ou pedaços). Serve à fila
#   (P2): o turno novo só segue quando a marca some ou deixa de ser de outro turno.
# - `fim_da_fala` (CHAVE_DO_FIM): o instante previsto em que a fala termina (ms epoch). Serve à espera da rajada (P1).
#
# Por que não reaproveita o TurnoEmCurso: aquela marca é aberta a cada mensagem do cliente e a mais nova toma; esta é do
# turno que está falando, e só ele a solta. As duas convivem.
#
# `ocupar`/`renovar`/`soltar` seguem o molde do TurnoEmCurso (TTL = teto do turno; renovar e soltar só do próprio turno,
# com WATCH/MULTI). O TTL é rede de segurança: o caminho normal sempre solta.
#
# Nunca levanta: é sinal de cortesia. Redis fora do ar quer dizer "ninguém ocupando, sem fim previsto", e o agente
# responde com a espera mínima.
module Autonomia::Agents::Operate::FalaEmCurso
  CHAVE_OCUPADA = 'autonomia:fala_em_curso:%<conversa>d'.freeze
  CHAVE_DO_FIM = 'autonomia:fim_da_fala:%<conversa>d'.freeze
  # Valores do fluxo externo: 160 ms por caractere (sorteado ±20% por fala), teto de 150 s, validade de 2,5 h.
  MS_POR_CARACTERE = 160
  VARIACAO = 0.2
  TETO_DO_FIM_MS = 150_000
  TTL_DO_FIM = 9000

  module_function

  def chave_ocupada(conversation_id) = format(CHAVE_OCUPADA, conversa: conversation_id)

  def chave_do_fim(conversation_id) = format(CHAVE_DO_FIM, conversa: conversation_id)

  def ocupar(conversation_id, message_id)
    ::Redis::Alfred.set(chave_ocupada(conversation_id), message_id.to_s, ex: ::Autonomia::Agents::Operate::TurnoEmCurso.teto_do_turno.to_i)
    nil
  rescue StandardError
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
  rescue StandardError
    false
  end

  def soltar(conversation_id, message_id)
    return if message_id.blank?

    ::Redis::Alfred.delete_if_equals(chave_ocupada(conversation_id), message_id.to_s)
    nil
  rescue StandardError
    nil
  end

  # Há marca e ela é de outro turno que não o `message_id`. Sem marca: false.
  def ocupada_por_outro?(conversation_id, message_id)
    dono = ::Redis::Alfred.get(chave_ocupada(conversation_id))
    dono.present? && dono != message_id.to_s
  rescue StandardError
    false
  end

  # Quanto a fala dura: caracteres x taxa (160 ms ± 20%, sorteada uma vez por fala), com teto.
  def duracao_estimada_ms(texto)
    minima = (MS_POR_CARACTERE * (1 - VARIACAO)).round
    maxima = (MS_POR_CARACTERE * (1 + VARIACAO)).round
    [texto.to_s.length * rand(minima..maxima), TETO_DO_FIM_MS].min
  end

  # Grava o fim previsto da fala (ms epoch). -> o instante gravado, ou nil se o Redis falhou.
  def prever_fim!(conversation_id, texto, agora: Time.current)
    fim = agora + (duracao_estimada_ms(texto) / 1000.0)
    ::Redis::Alfred.set(chave_do_fim(conversation_id), (fim.to_f * 1000).round, ex: TTL_DO_FIM)
    fim
  rescue StandardError
    nil
  end

  def fim_previsto(conversation_id)
    ms = ::Redis::Alfred.get(chave_do_fim(conversation_id))
    return if ms.blank?

    Time.zone.at(ms.to_i / 1000.0)
  rescue StandardError
    nil
  end
end
