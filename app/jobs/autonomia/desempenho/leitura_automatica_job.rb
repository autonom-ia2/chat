# A leitura automática diária do painel de desempenho (#2301). Roda às 07:00 UTC (`config/schedule.yml`).
# Sem conta, espalha: um job por conta com ficha de leitura, a flag `agentes_painel_desempenho` e o módulo de Agentes
# ligados, na fila `low`, com uma espera aleatória para as contas não lerem todas no mesmo minuto. Com conta, enfileira
# um LeituraDaFichaJob por agente da conta que tem ficha vigente com chave de leitura: a rodada de um agente que cai
# não segura a dos outros. A ordem é de quem leu há mais tempo (`na_vez`). Este job só lista (não paga nada), então
# fica com as novas tentativas padrão.
# Quem entra (conta e agente) é Autonomia::Desempenho::LeituraAutomatica::Elegivel, o mesmo critério do job da ficha.
# Tudo desligado enquanto a ENV AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA não for verdadeira.
class Autonomia::Desempenho::LeituraAutomaticaJob < ApplicationJob
  queue_as :low

  ESPALHAR_EM = 30.minutes.to_i
  VEZ_A_VEZ = 30

  def perform(account_id = nil)
    return unless ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador.ligada?
    return espalhar if account_id.nil?

    account = Account.find_by(id: account_id)
    return unless elegivel.conta?(account)

    na_vez(account, fichas(account)).each_with_index do |ficha, indice|
      ::Autonomia::Desempenho::LeituraDaFichaJob.set(wait: (indice * VEZ_A_VEZ).seconds).perform_later(account.id, ficha.id)
    end
  end

  private

  def espalhar
    Account.where(id: com_chave.select(:account_id)).find_each do |account|
      next unless elegivel.conta?(account)

      self.class.set(wait: rand(ESPALHAR_EM).seconds).perform_later(account.id)
    end
  end

  def elegivel = ::Autonomia::Desempenho::LeituraAutomatica::Elegivel

  # Quem leu há mais tempo vai primeiro (quem nunca leu, antes de todos): os agentes da conta rodam em fila e dividem o
  # teto do dia, então o primeiro da fila pode gastá-lo inteiro. Sem esta ordem, o mesmo agente ficaria sempre por
  # último e sem leitura. Os jobs saem com VEZ_A_VEZ segundos entre um e outro para a ordem valer.
  def na_vez(account, fichas)
    leu_em = ::Autonomia::Desempenho::Rodada.leram.where(account_id: account.id)
                                            .group(:sujeito_type, :sujeito_id).maximum(:iniciada_em)
    fichas.sort_by { |ficha| [leu_em[[ficha.sujeito_type, ficha.sujeito_id]] || Time.zone.at(0), ficha.id] }
  end

  def com_chave = ::Autonomia::Desempenho::Ficha.where.not(chave_de_leitura: [nil, ''])

  # A ficha vigente (a de maior versão) de cada agente da conta, só quando ela tem a chave de leitura e o agente existe
  # e está ligado (o robô de outro sistema, só que exista na conta).
  def fichas(account)
    sujeitos = ::Autonomia::Desempenho::Ficha.where(account_id: account.id).distinct.pluck(:sujeito_type, :sujeito_id)
    sujeitos.filter_map do |tipo, id|
      next unless elegivel.sujeito?(account, tipo, id)

      ficha = ::Autonomia::Desempenho::Ficha.vigente(account, tipo, id)
      ficha if ficha&.chave_de_leitura.present?
    end
  end
end
