# Cotar a renovação de um seguro fora da hora da resposta (E8, #2901): o "Nada mudou" (Carteira::Cotacao::Resposta) e a
# nova tentativa depois que o conferente da cotação não respondeu (`tentativa`, até Carteira::Cotacao::Cotar::TENTATIVAS).
class Carteira::Cotacao::CotarJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(apolice_id, vigencia, tentativa = 1)
    apolice, config = Carteira::Cotacao.da_vigencia(apolice_id, vigencia)
    return if apolice.nil?

    Carteira::Cotacao::Cotar.new(apolice, config, tentativa: tentativa).call
  end
end
