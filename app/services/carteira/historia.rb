# A história de um seguro no formato da tela (E4, #2897), do mais novo para o mais velho: o que aconteceu, quando, quem
# fez (nulo: o sistema) e, na correção, o que mudou. O texto de cada passo é do catálogo da tela, pelo `tipo`; daqui saem
# só os fatos. O valor que mudou vai em reais, como o seguro; no banco ele fica em centavos (Carteira::Campos).
class Carteira::Historia
  def initialize(apolice)
    @apolice = apolice
  end

  def call
    @apolice.eventos.order(quando: :desc, id: :desc).preload(:user).map do |evento|
      { tipo: evento.tipo, quando: evento.quando.to_i, quem: quem(evento.user), valores: evento.valores, acao: nil,
        mudancas: evento.mudancas&.map { |mudanca| como_a_tela_le(mudanca) } }
    end
  end

  private

  def quem(user)
    user && { id: user.id, nome: user.name }
  end

  def como_a_tela_le(mudanca)
    return mudanca unless mudanca['campo'] == Carteira::Campos::VALOR

    mudanca.merge('antes' => Carteira::Campos.em_reais(mudanca['antes']), 'depois' => Carteira::Campos.em_reais(mudanca['depois']))
  end
end
