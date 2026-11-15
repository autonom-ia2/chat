# O que foi lido de UM arquivo de uma leitura de PDF (E6, #2899), do jeito que quem usa precisa. É a única porta de
# `campos` e `duvidas` de um Carteira::LeituraItem (decisão D1 da E6.2): ninguém itera `campos` cru.
#
# Como o item guarda o que o leitor achou (Carteira::Leitor::Resultado), sem coluna nova:
# - nome com valor e fora de `duvidas`: achei, e vale ("certo");
# - nome com valor e em `duvidas`: achei, mas só vale depois de uma pessoa confirmar ("a confirmar": o telefone e o
#   e-mail do segurado, sempre, e o valor escrito sem "R$");
# - nome sem valor: não achei. "Não achei" nunca é mudança e nunca vira dado gravado.
# Os nomes são os do leitor (Carteira::Leitor::Resultado::NOMES). `DA_TELA` traduz para os campos da gaveta
# (Carteira::Campos).
#
# O que a pessoa escreve ou confirma no Conferir fica certo (`com`): o valor entra e o nome sai de `duvidas`. O que ela
# diz que não é do cliente (`sem`) vira "não achei".
#
# Os valores são dado de cliente: nada daqui vai para log, cache ou argumento de job. O `inspect` não os mostra.
class Carteira::ItemLido
  NOMES = Carteira::Leitor::Resultado::NOMES
  A_CONFIRMAR = Carteira::Leitor::Resultado::A_CONFIRMAR
  # campo da gaveta => nome do leitor
  DA_TELA = {
    'tipo' => 'tipo', 'seguradora' => 'seguradora', 'numero' => 'numero', 'comeca' => 'inicio_vigencia',
    'termina' => 'fim_vigencia', 'valor' => 'valor_centavos', 'bem' => 'bem'
  }.freeze
  # A marca, guardada no item ao trazer, de que a pessoa nasceu com este lote (o Desfazer só tira quem o lote criou).
  PESSOA_NOVA = 'pessoa_nova_em'.freeze

  def initialize(item)
    @campos = item.campos.to_h
    @duvidas = Array(item.duvidas)
  end

  def valor(nome)
    @campos[nome]
  end

  def certo?(nome)
    !valor(nome).nil? && @duvidas.exclude?(nome)
  end

  def a_confirmar?(nome)
    !valor(nome).nil? && @duvidas.include?(nome)
  end

  def nao_achei?(nome)
    valor(nome).nil?
  end

  def certo(nome)
    valor(nome) if certo?(nome)
  end

  # { nome => valor } do que está a confirmar.
  def a_confirmar
    NOMES.select { |nome| a_confirmar?(nome) }.index_with { |nome| valor(nome) }
  end

  # Quando a pessoa do item nasceu com o lote, ou nil.
  def pessoa_nova_em
    Time.zone.parse(@campos[PESSOA_NOVA].to_s) if @campos[PESSOA_NOVA].present?
  end

  # Os dados da apólice que podem ser gravados (Carteira::Guardar), só com o que está certo.
  def dados_da_apolice
    dados = Carteira::Leitor::Resultado::DA_APOLICE.index_with { |nome| certo(nome) }.symbolize_keys
    dados.merge(seguradora_chave: Carteira::Chave.seguradora(dados[:seguradora]).presence,
                numero_chave: Carteira::Chave.numero(dados[:numero]).presence)
  end

  # Os `campos` e as `duvidas` do item depois de a pessoa escrever, confirmar (`com`) ou recusar (`sem`) alguns nomes.
  def com(valores)
    { campos: @campos.merge(valores.stringify_keys), duvidas: @duvidas - valores.keys.map(&:to_s) }
  end

  def sem(nomes)
    nomes = nomes.map(&:to_s)
    { campos: @campos.merge(nomes.index_with { nil }), duvidas: @duvidas | nomes }
  end

  # O que o leitor devolveu, como o item guarda: o que está a confirmar fica em `campos` e o nome dele em `duvidas`.
  def self.do_resultado(resultado)
    { campos: resultado.campos.compact.merge(resultado.valores_a_confirmar),
      duvidas: (resultado.duvidas + resultado.a_confirmar).uniq }
  end

  def inspect
    "#<#{self.class.name} duvidas=#{@duvidas.size}>"
  end
end
