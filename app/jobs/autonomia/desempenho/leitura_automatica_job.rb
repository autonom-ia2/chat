# A leitura automática diária do painel de desempenho (#2301). Roda às 07:00 UTC (`config/schedule.yml`).
# Sem conta, espalha: um job por conta com ficha de leitura, a flag `agentes_painel_desempenho` e o módulo de Agentes
# ligados, na fila `low`, com uma espera aleatória para as contas não lerem todas no mesmo minuto. Com conta, enfileira
# um LeituraDaFichaJob por agente da conta que tem ficha vigente com chave de leitura: a rodada de um agente que cai
# não segura a dos outros. Este job só lista (não paga nada), então fica com as novas tentativas padrão.
# Tudo desligado enquanto a ENV AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA não for verdadeira.
class Autonomia::Desempenho::LeituraAutomaticaJob < ApplicationJob
  queue_as :low

  FLAG = 'agentes_painel_desempenho'.freeze
  ESPALHAR_EM = 30.minutes.to_i

  def perform(account_id = nil)
    return unless ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador.ligada?
    return espalhar if account_id.nil?

    account = Account.find_by(id: account_id)
    return unless ligada_na_conta?(account)

    fichas(account).each { |ficha| ::Autonomia::Desempenho::LeituraDaFichaJob.perform_later(account.id, ficha.id) }
  end

  private

  def espalhar
    Account.where(id: com_chave.select(:account_id)).find_each do |account|
      next unless ligada_na_conta?(account)

      self.class.set(wait: rand(ESPALHAR_EM).seconds).perform_later(account.id)
    end
  end

  def ligada_na_conta?(account)
    account&.active? && account.feature_enabled?(FLAG) && ::Autonomia::Agents::Config.enabled?(account)
  end

  def com_chave = ::Autonomia::Desempenho::Ficha.where.not(chave_de_leitura: [nil, ''])

  # A ficha vigente (a de maior versão) de cada agente da conta, só quando ela tem a chave de leitura e o agente existe
  # e está ligado (o robô de outro sistema, só que exista na conta).
  def fichas(account)
    sujeitos = ::Autonomia::Desempenho::Ficha.where(account_id: account.id).distinct.pluck(:sujeito_type, :sujeito_id)
    sujeitos.filter_map do |tipo, id|
      next unless ativo?(account, tipo, id)

      ficha = ::Autonomia::Desempenho::Ficha.vigente(account, tipo, id)
      ficha if ficha&.chave_de_leitura.present?
    end
  end

  def ativo?(account, tipo, id)
    return AgentBot.exists?(account_id: account.id, id: id) if tipo == 'robo'

    ::Autonomia::Agents::Agent.kept.exists?(account_id: account.id, id: id, enabled: true)
  end
end
