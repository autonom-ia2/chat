# O começo da cotação da renovação de um seguro (E8, #2901), pedido pelo card de renovação que acabou de nascer
# (Carteira::Cotacao::Gatilho). Uma vez só por seguro e vigência: o passo `cotacao_pedida` entra com o seguro travado e
# relido sob a trava, e o job repetido (ou o card recriado na mesma vigência) encontra o passo e não faz nada. Só então
# sai o "Algo mudou?" (Carteira::Cotacao::AlgoMudou).
#
# Sem nova tentativa: o passo já entrou, e repetir não mandaria nada. O que não sai vira `algo_mudou_nao_saiu` e aviso.
class Carteira::Cotacao::ComecarJob < ApplicationJob
  PEDIDA = 'cotacao_pedida'.freeze

  queue_as :default
  sidekiq_options retry: false

  def perform(apolice_id, vigencia)
    apolice, config = Carteira::Cotacao.da_vigencia(apolice_id, vigencia)
    return if apolice.nil? || !pedir!(apolice, config)

    Carteira::Cotacao::AlgoMudou.new(apolice, config).call
  end

  private

  def pedir!(apolice, config)
    apolice.with_lock(requires_new: true) do
      next false if Carteira::Cotacao.passo(apolice, PEDIDA)

      Carteira::Cotacao.registrar(apolice, PEDIDA, quem_cota: config.quem_cota, quem_envia: config.quem_envia)
      true
    end
  end
end
