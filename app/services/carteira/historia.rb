# A história de um seguro no formato da tela (E4, #2897), do mais novo para o mais velho: o que aconteceu, quando, quem
# fez (nulo: o sistema) e, na correção, o que mudou. O texto de cada passo é do catálogo da tela, pelo `tipo`; daqui saem
# só os fatos. O valor que mudou vai em reais, como o seguro; no banco ele fica em centavos (Carteira::Campos).
#
# O passo "o card de renovação nasceu" (E5, #2898) guarda o funil e quem cuida do card. Isso é do quadro: só sai para
# quem enxerga o card de renovação do seguro (Carteira::CardsVisiveis, a mesma régua de Carteira::Apresentacao). Para
# os outros, e quando o card não existe mais, o passo vem sem `valores`.
class Carteira::Historia
  DO_QUADRO = Carteira::Renovacao::CriarCard::NASCEU

  # quem: o contexto de quem pede, como o Pundit o recebe.
  def initialize(apolice, quem: nil)
    @apolice = apolice
    @quem = quem
  end

  def call
    @apolice.eventos.order(quando: :desc, id: :desc).preload(:user).map do |evento|
      { tipo: evento.tipo, quando: evento.quando.to_i, quem: quem(evento.user), valores: valores(evento), acao: nil,
        mudancas: evento.mudancas&.map { |mudanca| como_a_tela_le(mudanca) } }
    end
  end

  private

  def valores(evento)
    evento.tipo == DO_QUADRO && !ve_o_card? ? {} : evento.valores
  end

  def ve_o_card?
    return @ve_o_card if defined?(@ve_o_card)

    card = @apolice.crm_card_id
    @ve_o_card = card.present? && Carteira::CardsVisiveis.new(@quem).call.exists?(id: card)
  end

  def quem(user)
    user && { id: user.id, nome: user.name }
  end

  def como_a_tela_le(mudanca)
    return mudanca unless mudanca['campo'] == Carteira::Campos::VALOR

    mudanca.merge('antes' => Carteira::Campos.em_reais(mudanca['antes']), 'depois' => Carteira::Campos.em_reais(mudanca['depois']))
  end
end
