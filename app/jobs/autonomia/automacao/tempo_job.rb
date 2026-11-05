# A varredura dos gatilhos de tempo (#2499, PR3), a cada 15 minutos (config/schedule.yml). Enfileira um
# TempoDaAutomacaoJob por automação ligada com gatilho de tempo, só nas contas com o motor e a flag automacao_gatilhos
# (e o CRM, nos de card). A busca dos alvos fica no job de cada automação: uma conta grande não atrasa as outras.
class Autonomia::Automacao::TempoJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    rodada = ::Autonomia::Automacao::Tempo.rodada(Time.current).iso8601
    automacoes.find_each do |definicao|
      tipo = definicao.versao_ativa.receita.dig('gatilho', 'tipo')
      next unless ::Autonomia::Automacao::Gatilhos.disponivel?(tipo, definicao.account)

      ::Autonomia::Automacao::TempoDaAutomacaoJob.perform_later(definicao.id, rodada)
    rescue StandardError => e
      Rails.logger.error("[automacao][tempo] não enfileirou automacao=#{definicao.id} #{e.class} em #{e.backtrace&.first}")
    end
  end

  private

  def automacoes
    ::Autonomia::Automacao::Definicao.joins(:versao_ativa).where(ativa: true)
                                     .where("autonomia_automacao_versoes.receita -> 'gatilho' ->> 'tipo' IN (?)",
                                            ::Autonomia::Automacao::Gatilhos.de_tempo)
                                     .includes(:account, :versao_ativa)
  end
end
