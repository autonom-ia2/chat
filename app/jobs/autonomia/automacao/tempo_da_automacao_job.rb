# Uma automação com gatilho de tempo numa rodada da varredura (#2499, PR3): acha os alvos da janela e chama a Partida
# com a marca de cada um.
#
# Cada automação é processada no máximo uma vez por rodada, mesmo que o TempoJob atrase e duas varreduras encostem:
# - a marca da rodada no Redis barra o segundo job da mesma rodada;
# - a trava "rodando" barra a rodada seguinte enquanto esta não termina (e expira sozinha se o processo morrer).
# A marca única (automacao_id, evento) da execução é a garantia final: o mesmo fato nunca abre duas.
#
# Falha num alvo vai para o log (a classe e a linha, nunca a mensagem, que pode trazer dado do cliente) e não para os
# outros.
class Autonomia::Automacao::TempoDaAutomacaoJob < ApplicationJob
  queue_as :scheduled_jobs

  TRAVA = 15.minutes
  VALIDADE_DA_RODADA = 1.hour

  def perform(automacao_id, rodada)
    return unless Redis::Alfred.set("automacao:tempo:rodada:#{automacao_id}:#{rodada}", 1, nx: true, ex: VALIDADE_DA_RODADA.to_i)

    trava = "automacao:tempo:rodando:#{automacao_id}"
    dono = SecureRandom.uuid
    return unless Redis::Alfred.set(trava, dono, nx: true, ex: TRAVA.to_i)

    begin
      varrer(automacao_id)
    ensure
      # Só solta a própria trava: se esta rodada passou de TRAVA, a trava pode já ser de outra.
      Redis::Alfred.delete_if_equals(trava, dono)
    end
  end

  private

  def varrer(automacao_id)
    definicao = ::Autonomia::Automacao::Definicao.includes(:account, :versao_ativa).find_by(id: automacao_id)
    gatilho = definicao&.versao_ativa&.receita&.dig('gatilho').to_h
    tipo = gatilho['tipo']
    return unless definicao&.ativa && ::Autonomia::Automacao::Gatilhos.de_tempo?(tipo) &&
                  ::Autonomia::Automacao::Gatilhos.disponivel?(tipo, definicao.account)

    busca = ::Autonomia::Automacao::Tempo.busca(tipo).new(definicao: definicao, gatilho: gatilho, agora: Time.current)
    busca.cada { |alvo, marca| comecar(definicao, alvo, tipo, marca) }
  end

  def comecar(definicao, alvo, tipo, marca)
    ::Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: tipo, evento: marca).call
  rescue StandardError => e
    Rails.logger.error("[automacao][tempo] não começou automacao=#{definicao.id} alvo=#{alvo.class.name}:#{alvo.id} #{e.class} " \
                       "em #{e.backtrace&.first}")
  end
end
