# "Dar o prêmio" pela ficha (#3100): tira a meta do cartão da pessoa e anota quem deu. Só com o cartão completo: a
# conferência acontece com a linha do saldo travada (Fidelidade::Carteira, `exige`), então dois toques ao mesmo tempo
# não tiram a meta duas vezes de quem só completou uma. O que passa da meta fica para o próximo cartão.
#
# Quem pode (decisão D1 do Rodrigo, 23/11): quem pode mexer no contato, inclusive o atendente (o controller confere).
class Fidelidade::DarPremio
  def initialize(programa, contato, user)
    @programa = programa
    @contato = contato
    @user = user
  end

  # Devolve o movimento do prêmio. Levanta Fidelidade::Carteira::SaldoInsuficiente sem o cartão completo.
  def call
    Fidelidade::Carteira.new(@programa, @contato)
                        .sair(tipo: Fidelidade::Movimento::PREMIO, quantos: @programa.meta, exige: @programa.meta, user: @user)
  end
end
