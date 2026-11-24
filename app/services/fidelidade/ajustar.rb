# Dar ou tirar carimbos à mão (#3100), com o motivo e quem fez. Só com `fidelidade_manage` (decisão D1 do Rodrigo,
# 23/11; o controller confere). Tirar mais do que a pessoa tem é recusado (SaldoInsuficiente): o saldo nunca fica
# negativo e quem ajusta fica sabendo. Dar à mão que completa o cartão dispara o gatilho, como a compra.
class Fidelidade::Ajustar
  def initialize(programa, contato, user)
    @programa = programa
    @contato = contato
    @user = user
  end

  # `quantos`: com sinal, diferente de zero. Devolve o movimento.
  def call(quantos, motivo)
    carteira = Fidelidade::Carteira.new(@programa, @contato)
    atributos = { tipo: Fidelidade::Movimento::AJUSTE, user: @user, motivo: motivo.presence }
    movimento = if quantos.positive?
                  carteira.entrar(quantos: quantos, **atributos)
                else
                  carteira.sair(quantos: -quantos, exige: -quantos, **atributos)
                end
    Fidelidade::CartaoCompleto.avisar(@programa.account, [[@contato, movimento]]) if carteira.completou?
    movimento
  end
end
