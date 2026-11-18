# Acompanha a cotação da renovação aberta no portal (E8, #2901): uma leitura por vez, pela própria ferramenta de cotação
# (`poll` de Native::InsuranceQuote, com a execução), que grava o resultado por seguradora no handle e, quando a cotação
# fecha, gera o comparativo em PDF. Fechou: Carteira::Cotacao::Pronta guarda a proposta e segue. Ainda chegando: lê de
# novo em INTERVALO, até LEITURAS vezes. Passou do teto, falhou, ou a leitura quebrou na última vez: a execução fecha
# e a equipe é avisada (`proposta_nao_saiu`).
#
# A leitura não é paga. Sem nova tentativa do Sidekiq: a próxima leitura é o job seguinte.
class Carteira::Cotacao::AcompanharJob < ApplicationJob
  LEITURAS = 40
  INTERVALO = 20.seconds
  Quote = Autonomia::Agents::Tools::Native::InsuranceQuote

  queue_as :default
  sidekiq_options retry: false

  def perform(run_id, apolice_id, leitura = 0)
    run = Autonomia::Agents::ToolRun.find_by(id: run_id)
    apolice = Carteira::Apolice.find_by(id: apolice_id)
    return unless run&.running? && apolice

    progresso = ler(run, leitura)
    return de_novo(run, apolice, leitura) if progresso.nil? || progresso.running?
    return Carteira::Cotacao::Pronta.new(apolice, run, progresso).call if progresso.done?

    fechar(run, apolice, progresso.failure_code)
  end

  private

  def ler(run, leitura)
    progresso = Quote.new(agent: run.agent, params: run.arguments, run: run).poll(handle: run.handle.to_h, attempt: leitura)
    run.record_attempt!(handle: progresso.handle) if progresso.running? && progresso.handle
    progresso
  rescue StandardError => e
    Rails.logger.warn("[carteira][cotacao] leitura falhou run=#{run.id} #{e.class}")
    nil
  end

  def de_novo(run, apolice, leitura)
    return fechar(run, apolice, 'prazo') if leitura + 1 >= LEITURAS

    self.class.set(wait: INTERVALO).perform_later(run.id, apolice.id, leitura + 1)
  end

  def fechar(run, apolice, codigo)
    run.finish!('failed', failure_code: codigo.presence || 'falhou')
    Carteira::Cotacao.registrar(apolice, Carteira::Cotacao::Cotar::NAO_SAIU, motivo: 'cotacao_falhou', detalhe: codigo)
    Carteira::Cotacao::Aviso.new(apolice, 'proposta_nao_saiu', detalhe: 'cotacao_falhou').call
  end
end
