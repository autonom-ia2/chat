# O seguro de uma linha da planilha (E4, #2897), lido das colunas de seguro para as colunas da apólice, e o que falta
# nele. É a mesma leitura na conferência (Carteira::Trazer::ProblemasDeSeguro, que aponta as linhas que precisam da
# pessoa) e na gravação (Carteira::Trazer::SeguroDaLinha): o que a tela aprovou é o que entra.
#
# `motivos` são códigos, na ordem em que a tela os mostra; nenhum carrega o texto da célula:
# - o número em branco, ou em notação científica ("1.23457E+15"): o Excel trocou os últimos dígitos por zero, e gravar
#   isso juntaria apólices diferentes;
# - a seguradora em branco;
# - o fim da vigência em branco, que não é data, ou antes do começo;
# - o começo que não é data; o valor que não é número.
# O ramo fica como veio (`ramo`): quem decide o tipo é Carteira::Trazer::TipoDoRamo. Começo, valor e bem podem faltar.
# Em `atributos` só entra o que deu para ler: o resto fica nil.
class Carteira::Trazer::SeguroLido
  Lido = Struct.new(:atributos, :ramo, :motivos, keyword_init: true) do
    def completo?
      motivos.empty?
    end

    def chave
      atributos.values_at(:seguradora_chave, :numero_chave)
    end
  end
  INVALIDO = Carteira::Trazer::Leitores::INVALIDO
  EXPOENTE = 'E+'.freeze

  # valores: { 'numero' => 'EX-001234', 'seguradora' => '…', 'tipo' => 'Automóvel', 'comeca' => '', 'termina' => '10/03/2027',
  #            'valor' => 'R$ 3.410,00', 'bem' => '…' } (Carteira::Trazer::ColunasDeSeguro#valores).
  def self.call(valores)
    new(valores).call
  end

  def initialize(valores)
    @valores = valores
    @motivos = []
  end

  def call
    atributos = numero.merge(seguradora, vigencia, valor, bem: @valores['bem'].presence)
    Lido.new(atributos: atributos, ramo: @valores['tipo'].presence, motivos: @motivos)
  end

  private

  def numero
    texto = @valores['numero'].to_s
    chave = Carteira::Chave.numero(texto)
    @motivos << 'seguro_numero_falta' if chave.empty?
    @motivos << 'seguro_numero_cientifico' if cientifico?(texto)
    { numero: texto.presence, numero_chave: chave.presence }
  end

  # "1.23457E+15" e "1,23457E+15": um número com expoente, que nenhuma seguradora escreve numa apólice.
  def cientifico?(texto)
    numero = texto.upcase.tr(',', '.')
    numero.include?(EXPOENTE) && !Float(numero, exception: false).nil?
  end

  def seguradora
    texto = @valores['seguradora'].to_s
    chave = Carteira::Chave.seguradora(texto)
    @motivos << 'seguro_seguradora_falta' if chave.empty?
    { seguradora: texto.presence, seguradora_chave: chave.presence }
  end

  def vigencia
    termina = data('termina', falta: 'seguro_termina_falta', invalida: 'seguro_termina_invalida')
    comeca = data('comeca', invalida: 'seguro_comeca_invalida')
    @motivos << 'seguro_termina_antes' if comeca && termina && termina < comeca
    { inicio_vigencia: comeca, fim_vigencia: termina }
  end

  def data(campo, invalida:, falta: nil)
    lida = Carteira::Trazer::Leitores.data(@valores[campo])
    @motivos << falta if lida.nil? && falta
    @motivos << invalida if lida == INVALIDO
    lida unless lida == INVALIDO
  end

  def valor
    centavos = Carteira::Trazer::Leitores.centavos(@valores['valor'])
    @motivos << 'seguro_valor_invalido' if centavos == INVALIDO
    { valor_centavos: (centavos unless centavos == INVALIDO) }
  end
end
