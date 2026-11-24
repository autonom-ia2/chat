# Os três números do painel da Fidelidade (#3100, PainelDoCartao): quantos clientes têm carimbos no cartão, quantos
# estão perto do prêmio (falta até 20% da meta, sem ter completado: Fidelidade::Programa#perto_a_partir) e quantos
# prêmios foram dados nos últimos 30 dias. Lê o saldo pronto (Fidelidade::Saldo), sem somar movimentos.
class Fidelidade::Resumo
  JANELA_DOS_PREMIOS = 30.days

  def initialize(programa, agora = Time.current)
    @programa = programa
    @agora = agora
  end

  def call
    saldos = Fidelidade::Saldo.where(programa_id: @programa.id)
    { com_saldo: saldos.where('saldo > 0').count,
      perto: saldos.where(saldo: @programa.perto_a_partir...@programa.meta).count,
      completos: saldos.where(saldo: @programa.meta..).count,
      premios_30d: premios }
  end

  private

  def premios
    Fidelidade::Movimento.where(programa_id: @programa.id, tipo: Fidelidade::Movimento::PREMIO,
                                created_at: (@agora - JANELA_DOS_PREMIOS)..).count
  end
end
