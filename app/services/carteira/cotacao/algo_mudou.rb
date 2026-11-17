# O "Algo mudou?" da renovação (E8, #2901): o primeiro contato, que sai sozinho nos dois modos de envio, pelo modelo da
# Finalidade `renovacao_algo_mudou` (Carteira::Cotacao::Envio, com as conferências de recusa, caixa e modelo). Saiu: em
# DIAS_SEM_RESPOSTA, sem resposta, a cotação segue com o que está na apólice (Carteira::Cotacao::SemRespostaJob). Não
# saiu: `algo_mudou_nao_saiu` com o motivo e aviso à equipe, e a cotação para (a proposta sairia pela mesma caixa).
class Carteira::Cotacao::AlgoMudou
  FINALIDADE = 'renovacao_algo_mudou'.freeze
  NAO_SAIU = 'algo_mudou_nao_saiu'.freeze

  def initialize(apolice, config)
    @apolice = apolice
    @config = config
  end

  def call
    Carteira::Cotacao::Envio.new(@apolice, @config).modelo(FINALIDADE, Carteira::Cotacao::ETAPA_ALGO_MUDOU)
    Carteira::Cotacao::SemRespostaJob.set(wait: Carteira::Cotacao::DIAS_SEM_RESPOSTA.days)
                                     .perform_later(@apolice.id, @apolice.fim_vigencia.iso8601)
  rescue Carteira::Cotacao::Envio::NaoSaiu => e
    nao_saiu(e.message)
  rescue StandardError => e
    Rails.logger.warn("[carteira][cotacao] algo mudou nao saiu apolice=#{@apolice.id} #{e.class}")
    nao_saiu('erro')
  end

  private

  def nao_saiu(motivo)
    Carteira::Cotacao.registrar(@apolice, NAO_SAIU, motivo: motivo)
    Carteira::Cotacao::Aviso.new(@apolice, NAO_SAIU, detalhe: motivo).call
  end
end
