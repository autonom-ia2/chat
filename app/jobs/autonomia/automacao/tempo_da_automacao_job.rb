# Uma automação com gatilho de tempo numa rodada da varredura (#2499, PR3): acha os alvos da janela e chama a Partida
# com a marca de cada um.
#
# Cada automação é processada no máximo uma vez por rodada, mesmo que o TempoJob atrase e duas varreduras encostem:
# - a marca da rodada no Redis barra o segundo job da mesma rodada;
# - a trava "rodando" barra as rodadas seguintes enquanto esta não termina, até TRAVA (expira sozinha se o processo
#   morrer). Uma varredura mais longa que TRAVA encosta na seguinte: é trabalho em dobro, nunca execução em dobro.
# A marca única (automacao_id, evento) da execução é a garantia final: o mesmo fato nunca abre duas.
#
# Falha num alvo vai para o log (a classe e a linha, nunca a mensagem, que pode trazer dado do cliente) e não para os
# outros. No fim, o job falha com o primeiro erro, para aparecer no Sidekiq. Sem nova tentativa: a próxima rodada, em
# 15 minutos, é a nova tentativa (a janela é de 1 dia e a marca não deixa repetir o que já começou).
class Autonomia::Automacao::TempoDaAutomacaoJob < ApplicationJob
  queue_as :scheduled_jobs
  sidekiq_options retry: false

  TRAVA = 1.hour
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
    return unless definicao && de_tempo_ligada?(definicao, tipo)

    busca = ::Autonomia::Automacao::Tempo.busca(tipo).new(definicao: definicao, gatilho: gatilho, agora: Time.current)
    erro = cada_alvo(busca, definicao, tipo)
    raise erro if erro
  end

  def de_tempo_ligada?(definicao, tipo)
    definicao.ativa && ::Autonomia::Automacao::Gatilhos.de_tempo?(tipo) && ::Autonomia::Automacao::Gatilhos.disponivel?(tipo, definicao.account)
  end

  # O primeiro erro dos alvos, ou nil.
  def cada_alvo(busca, definicao, tipo)
    primeiro_erro = nil
    busca.cada { |alvo, marca| primeiro_erro ||= comecar(definicao, alvo, tipo, marca) }
    primeiro_erro
  end

  # O erro do alvo, ou nil.
  def comecar(definicao, alvo, tipo, marca)
    ::Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: tipo, evento: marca).call
    nil
  rescue StandardError => e
    Rails.logger.error("[automacao][tempo] não começou automacao=#{definicao.id} alvo=#{alvo.class.name}:#{alvo.id} #{e.class} " \
                       "em #{e.backtrace&.first}")
    e
  end
end
