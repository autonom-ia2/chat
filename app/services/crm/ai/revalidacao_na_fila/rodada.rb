# As releituras de uma rodada da fila (HandoffDrainJob): a cota conta só as que deram resposta, e uma releitura só
# começa se cabe inteira (RevalidaPassagem::TIMEOUT + folga) no que sobra da rodada. Fora da cota ou do tempo, a
# conversa fica para a rodada seguinte, sem entregar sem reler.
class Crm::Ai::RevalidacaoNaFila::Rodada
  def initialize(cota:, fim:, folga:, com_trava:)
    @cota = cota
    @fim = fim
    @folga = folga
    @com_trava = com_trava
    @feitas = 0
  end

  # true: não entrega nesta rodada (o pedido foi superado e a marca saiu, a resposta ficou velha, ou não há cota ou
  # tempo para reler). Falha da releitura: false, e a entrega segue como antes.
  def segurar?(conversation)
    revalidacao = Crm::Ai::RevalidacaoNaFila.new(conversation, com_trava: @com_trava)
    return false unless revalidacao.precisa?
    return true if @feitas >= @cota || !cabe?

    resultado = revalidacao.call
    @feitas += 1 unless resultado.falhou
    resultado.superado || resultado.adiar
  end

  private

  def cabe?
    @fim - Process.clock_gettime(Process::CLOCK_MONOTONIC) > Crm::Ai::RevalidaPassagem::TIMEOUT + @folga
  end
end
