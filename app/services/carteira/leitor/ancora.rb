# "O que o modelo devolveu está escrito nas páginas?" (E6, #2899). O leitor nunca confia num valor só porque o modelo o
# devolveu: cada campo precisa estar nas páginas que foram enviadas, senão vira "não achei". É comparação de valor, não
# interpretação de texto: quem entende a apólice é o modelo; aqui só se confere que ele não inventou.
#
# - texto (seguradora, ramo, bem, nome): cada palavra do valor aparece nas páginas, sem contar espaço, caixa, acento
#   e pontuação (a forma de comparação da casa, Carteira::Chave);
# - número da apólice: letras e dígitos do valor aparecem juntos, na ordem;
# - CPF e CNPJ: os 11 ou 14 dígitos aparecem juntos, na ordem;
# - data: o dia, o mês e o ano aparecem juntos como dígitos (12/11/2026, 2026-11-12 ou 12/11/26). Data escrita por
#   extenso não se confirma e vira "não achei";
# - valor: os dígitos dos centavos aparecem juntos (R$ 1.234,56 e 123456); valor redondo também vale sem os centavos.
#
# Sem regex: dígitos e letras saem por método de texto.
class Carteira::Leitor::Ancora
  SO_DIGITOS = '^0-9'.freeze
  TAMANHOS_DE_DOCUMENTO = [11, 14].freeze
  MAXIMO_DO_TEXTO = 200
  FORMAS_DA_DATA = %w[%d%m%Y %Y%m%d %d%m%y].freeze
  CENTAVOS_POR_REAL = 100

  def self.digitos(texto)
    texto.to_s.delete(SO_DIGITOS)
  end

  def initialize(texto)
    @digitos = self.class.digitos(texto)
    @letras_e_digitos = Carteira::Chave.seguradora(texto)
  end

  # O texto como veio, sem espaço sobrando; nil quando alguma palavra dele não está nas páginas.
  def escrito(valor)
    return unless valor.is_a?(String)

    texto = valor.squish
    texto if texto.length <= MAXIMO_DO_TEXTO && palavras_escritas?(texto)
  end

  def codigo(valor)
    return unless valor.is_a?(String)

    chave = Carteira::Chave.seguradora(valor)
    valor.squish if chave.present? && @letras_e_digitos.include?(chave)
  end

  # Só os dígitos do CPF ou do CNPJ.
  def documento(valor)
    digitos = self.class.digitos(valor)
    digitos if TAMANHOS_DE_DOCUMENTO.include?(digitos.length) && tem_digitos?(digitos)
  end

  # A data como AAAA-MM-DD.
  def data(valor)
    return unless valor.is_a?(String)

    data = Date.iso8601(valor)
    data.iso8601 if FORMAS_DA_DATA.any? { |forma| tem_digitos?(data.strftime(forma)) }
  rescue Date::Error
    nil
  end

  def centavos(valor)
    return unless valor.is_a?(Integer) && valor.positive?

    redondo = (valor % CENTAVOS_POR_REAL).zero? && tem_digitos?((valor / CENTAVOS_POR_REAL).to_s)
    valor if tem_digitos?(valor.to_s) || redondo
  end

  def tem_digitos?(digitos)
    digitos.present? && @digitos.include?(digitos)
  end

  private

  def palavras_escritas?(texto)
    palavras = texto.split.map { |palavra| Carteira::Chave.seguradora(palavra) }.reject(&:empty?)
    palavras.any? && palavras.all? { |palavra| @letras_e_digitos.include?(palavra) }
  end
end
