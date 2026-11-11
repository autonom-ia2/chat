# Um código da tabela da NCM já lido (#2858, revisão do #2917): os dígitos, o texto do próprio nível sem HTML, sem os
# traços do começo e sem o ":" do fim (`propria`), e quantos traços abriam a descrição (`tracos`, o nível na tabela).
# Cada item passa uma vez só pelo Nokogiri: a busca "outros" traz mais de 3.000 itens, e a descrição completa de cada
# código lê o texto dos pais dele.
class Autonomia::FerramentasProntas::Fontes::Ncm::Nivel
  attr_reader :codigo, :digitos, :propria, :tracos, :vigente_desde

  # O item fora do formato (sem código, sem descrição, ou com a descrição feita só de tags): falha, e o agente ouve
  # "não consegui".
  def self.de(dado)
    ou_nil(dado) || raise(Autonomia::FerramentasProntas::Provedor::Falha, 'resposta_invalida')
  end

  # nil no lugar da falha: o item fora do formato que veio na chamada a mais é deixado de lado.
  def self.ou_nil(dado)
    return unless dado.is_a?(Hash) && dado['codigo'].present? && dado['descricao'].present?

    texto = Autonomia::FerramentasProntas::Fontes::Ncm.texto(dado['descricao'])
    propria = Autonomia::FerramentasProntas::Fontes::Ncm::Descricao.limpa(texto)
    new(dado, texto, propria) unless propria.empty?
  end

  def initialize(dado, texto, propria)
    @codigo = dado['codigo'].to_s.strip
    @digitos = Autonomia::FerramentasProntas::Fontes::Ncm.digitos(@codigo)
    @propria = propria
    @tracos = texto.each_char.take_while { |caractere| ['-', ' '].include?(caractere) }.count('-')
    @vigente_desde = dado['data_inicio'].presence
  end

  # O grupo que o modelo pode buscar pelo código: posição, subposição ou item (4 a 7 dígitos). O capítulo, não (a busca
  # pede ao menos 3 letras).
  def self.grupo?(digitos)
    digitos.length.between?(Autonomia::FerramentasProntas::Fontes::Ncm::POSICAO, Autonomia::FerramentasProntas::Fontes::Ncm::DA_NOTA - 1)
  end

  def da_nota?
    digitos.length == Autonomia::FerramentasProntas::Fontes::Ncm::DA_NOTA
  end
end
