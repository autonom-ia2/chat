# Cria um cupom da conta (#3100, MontarCupom) e o pausa ou liga de novo (LinhaDoCupom).
#
# A oferta chega como a tela fala: { tipo, valor, texto }. Em `porcentagem` o valor é a %; em `valor`, reais inteiros
# (ficam em centavos); em `presente`, vale o texto. Cada cliente usa uma vez (regra fixa nesta fase). O cupom nasce
# ligado. Pausar só para de mandar: quem já recebeu o código continua podendo usar até a validade dele.
#
# Devolve o cupom; com algo errado, o cupom com os erros (`errors`), sem gravar.
class Fidelidade::GravarCupom
  CAMPOS = [:nome, :prefixo, :validade_dias, { oferta: %i[tipo valor texto] }].freeze

  def initialize(account, user)
    @account = account
    @user = user
  end

  def criar(dados)
    oferta = dados[:oferta].respond_to?(:to_h) ? dados[:oferta].to_h.with_indifferent_access : {}
    tipo = oferta[:tipo].to_s
    cupom = Fidelidade::Cupom.new(
      account: @account, created_by: @user, nome: dados[:nome].to_s.strip, oferta_tipo: tipo,
      oferta_valor: valor_da_oferta(tipo, oferta[:valor]), oferta_texto: (oferta[:texto].to_s.strip if tipo == Fidelidade::Cupom::PRESENTE),
      moeda: Fidelidade::Programa::MOEDA, prefixo: dados[:prefixo].to_s.strip.upcase, validade_dias: inteiro(dados[:validade_dias]),
      limite_por_cliente: 1, ligado: true
    )
    cupom.save
    cupom
  end

  def ligar(cupom, ligado)
    cupom.update!(ligado: ligado) unless cupom.ligado == ligado
    cupom
  end

  private

  def valor_da_oferta(tipo, valor)
    numero = inteiro(valor)
    return if numero.nil? || tipo == Fidelidade::Cupom::PRESENTE

    tipo == Fidelidade::Cupom::VALOR ? numero * Fidelidade::TextoDoCupom::CENTAVOS : numero
  end

  def inteiro(valor) = Integer(valor.to_s, 10, exception: false)
end
