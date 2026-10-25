# O TURNO DO AGENTE ESTÁ EM CURSO (#2154, revisões). Com a flag `agente_so_informa`, a IA de Atribuição que avalia depois
# da fala do agente (Crm::Ai::AvaliacaoDepoisDaFala) não entrega a conversa enquanto o agente está respondendo o turno
# seguinte: na janela do debounce, na espera do assunto, na chamada de IA (a Lia faz até 6 rodadas) ou "digitando" em
# pedaços. Entregar ali fazia o Responder cair em `nao_elegivel` e a resposta inteira se perdia, ou cortava a fala no
# meio. Ela espera e tenta de novo (com teto).
#
# Os sinais que já existiam não dizem isso: a marca do debounce do ReplyJob (`pending_message_id`) não é limpa depois da
# resposta, a posse do turno (PosseDoTurno) dura um dia de propósito, e o token de cada pedaço só existe depois que ele
# sai. Por isso uma chave no Redis, por conversa, com o id da mensagem do cliente que abriu o turno:
#
# - `abrir`: o ReplyJob#trigger, a cada mensagem do cliente (a mais nova vence, como no debounce). TTL = teto do turno.
# - `renovar`: só se a chave ainda é deste turno (compare-and-expire, WATCH/MULTI como o Redis::Alfred.delete_if_equals:
#   se a chave muda entre a leitura e o EXPIRE, a transação aborta). O Responder antes de agendar a cadeia, e cada
#   pedaço agendado, com o TTL da cadeia.
# - `soltar`: só se ainda é deste turno (compare-and-delete). O Responder num `ensure` (clássico, voz, silêncio, falha),
#   salvo quando a cadeia assumiu ou o turno foi refeito por outro dono; a cadeia, quando termina; o settle do ReplyJob,
#   quando não chega ao Responder.
#
# O TTL é a rede de segurança para um job que morreu no meio; o caminho normal sempre solta. Nunca levanta: é um sinal
# de cortesia, e a entrega segue sem ele.
module Autonomia::Agents::Operate::TurnoEmCurso
  CHAVE = 'autonomia:turno_em_curso:%<conversa>d'.freeze
  # A maior pausa entre dois pedaços é 30 s (clamp do ChunkedDeliveryJob); renovada a cada pedaço.
  TTL_DA_CADEIA = 2.minutes

  module_function

  # O teto real de um turno, das configurações: a maior janela de debounce, a maior espera do assunto, a maior chamada de
  # IA (a Lia: RODADAS_DA_LIA rodadas, cada uma com as rodadas de ferramenta do especialista e mais uma chamada, a mesma
  # conta do QuoteAgent::Builder.rodadas_do_turno; o agente com ajudante: o prazo da resposta) e a cadeia de pedaços.
  def teto_do_turno
    runner = ::Autonomia::Agents::Specialists::Runner
    lia = ::Autonomia::Insurance::QuoteAgent::Builder::RODADAS_DA_LIA * (runner::SEGUNDOS_DE_FERRAMENTA + runner::SEGUNDOS_POR_CHAMADA)
    ia = [lia, ::Autonomia::Agents::Ajudantes::PRAZO_DA_RESPOSTA, ::Crm::Ai::ResponsesClient::REQUEST_TIMEOUT].max
    cadeia = ::Autonomia::Agents::Config::HUMANIZE[:max_total_delay_ms] / 1000
    ::Autonomia::Agents::Config::OPERATE_DEBOUNCE_MAX_SECONDS + ::Autonomia::Agents::Operate::EsperaDoAssunto::TETO + (ia + cadeia).seconds
  end

  def abrir(conversation_id, message_id)
    ::Redis::Alfred.set(chave(conversation_id), message_id.to_s, ex: teto_do_turno.to_i)
  rescue StandardError
    nil
  end

  # -> true quando renovou (a marca era deste turno).
  def renovar(conversation_id, message_id, ttl = TTL_DA_CADEIA)
    chave = chave(conversation_id)
    ::Redis::Alfred.with do |redis|
      redis.watch(chave) do
        next redis.unwatch && false unless redis.get(chave) == message_id.to_s

        Array(redis.multi { |transacao| transacao.expire(chave, ttl.to_i) }).first.present?
      end
    end
  rescue StandardError
    false
  end

  def soltar(conversation_id, message_id)
    return if message_id.blank?

    ::Redis::Alfred.delete_if_equals(chave(conversation_id), message_id.to_s)
  rescue StandardError
    nil
  end

  def em_curso?(conversation_id)
    ::Redis::Alfred.exists?(chave(conversation_id))
  rescue StandardError
    false
  end

  def chave(conversation_id) = format(CHAVE, conversa: conversation_id)
end
