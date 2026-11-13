# O que muda numa apólice guardada quando ela chega de novo (E4, #2897), campo a campo, para Carteira::Guardar.
#
# Só o tipo, o começo, o fim, o valor e o bem podem mudar. Não muda:
# - o campo que não veio (nil): a fonte que não sabe não apaga;
# - o campo corrigido à mão na gaveta (`corrigido_a_mao`);
# - o tipo decidido, quando o que chega é `outro` (é o "não sei" de quem classifica o ramo);
# - na fonte mais fraca que a da apólice, o campo que já tem valor: ela só preenche o que está vazio.
#
# `lista` é o que a história guarda ([{ campo:, antes:, depois: }], com os nomes da tela e os valores na forma do
# banco: Carteira::Campos) e `colunas` o que gravar na apólice. O ramo como veio acompanha o tipo.
class Carteira::Guardar::Mudancas
  CAMPOS = %w[tipo comeca termina valor bem].freeze
  TIPO = 'tipo'.freeze
  OUTRO = 'outro'.freeze

  def initialize(apolice, dados, mais_fraca:)
    @apolice = apolice
    @dados = dados
    @mais_fraca = mais_fraca
  end

  def lista
    @lista ||= CAMPOS.filter_map do |campo|
      coluna = Carteira::Campos::COLUNAS.fetch(campo)
      next unless muda?(campo, coluna)

      antes = Carteira::Campos.guardado(@apolice[coluna])
      depois = Carteira::Campos.guardado(@dados[coluna])
      { campo: campo, antes: antes, depois: depois } unless antes == depois
    end
  end

  def nenhuma?
    lista.empty?
  end

  def colunas
    colunas = lista.map { |mudanca| Carteira::Campos::COLUNAS.fetch(mudanca[:campo]) }
    colunas.include?(:tipo) ? @dados.slice(*colunas, :ramo_original) : @dados.slice(*colunas)
  end

  private

  def muda?(campo, coluna)
    return false if @dados[coluna].nil? || @apolice.corrigido_a_mao.include?(campo)
    return false if campo == TIPO && @dados[coluna] == OUTRO

    !@mais_fraca || @apolice[coluna].blank?
  end
end
