# UMA TABELA OFICIAL DE CÓDIGO E NOME, lida de um arquivo do repositório (#2858, F4): a TUSS dos procedimentos e a
# CID-10 das doenças, que não têm API aberta. O provedor é local (`HOST = nil`): sem rede, sem teto e sem cache (a
# tabela já está aqui). Cada fonte é uma subclasse com `NOME` e `ARQUIVO` (CSV com cabeçalho `codigo;nome`, em UTF-8).
#   - pelo código: o nome oficial; o código da tabela e o pedido passam pela mesma `chave` (`Parametro` da fonte);
#   - pela busca: todas as palavras no nome, sem acento e sem caixa (`Lista.filtrar`), com o total e no máximo `MAXIMO`.
# O arquivo que falta (ainda não baixado) é falha da fonte (`tabela_ausente`), não "não tem".
# Fica na pasta dos procedimentos porque nasceu com eles; a CID-10 (`doencas/cid10.rb`) herda daqui.
class Autonomia::FerramentasProntas::Fontes::Procedimentos::TabelaLocal < Autonomia::FerramentasProntas::Provedor
  HOST = nil
  MAXIMO = 20
  SEPARADOR = ';'.freeze

  Item = Data.define(:codigo, :nome)

  class << self
    def itens
      @itens ||= {}
      @itens[self::ARQUIVO.to_s] ||= ler
    end

    # A chave de comparação do código (a da fonte: só dígitos na TUSS, sem ponto e em maiúscula na CID-10).
    def chave(codigo)
      codigo.to_s.strip
    end

    # O código como vai ao modelo.
    def exibir(codigo)
      codigo
    end

    def por_codigo
      @por_codigo ||= {}
      @por_codigo[self::ARQUIVO.to_s] ||= itens.each_with_object({}) { |item, indice| indice[chave(item.codigo)] ||= item }.freeze
    end

    private

    def ler
      raise Autonomia::FerramentasProntas::Provedor::Falha, 'tabela_ausente' unless File.exist?(self::ARQUIVO)

      CSV.foreach(self::ARQUIVO, headers: true, col_sep: SEPARADOR, encoding: 'bom|utf-8').filter_map do |linha|
        codigo = linha['codigo'].to_s.strip
        nome = linha['nome'].to_s.squish
        Item.new(codigo: codigo, nome: nome) if codigo.present? && nome.present?
      end.freeze
    rescue CSV::MalformedCSVError
      raise Autonomia::FerramentasProntas::Provedor::Falha, 'tabela_invalida'
    end
  end

  def consultar(consulta, params)
    return pelo_codigo(params.fetch('codigo')) if consulta.nome == 'codigo'

    pela_busca(params.fetch('busca'))
  end

  private

  def pelo_codigo(codigo)
    item = self.class.por_codigo[self.class.chave(codigo)]
    raise NaoEncontrado if item.nil?

    { 'codigo' => self.class.exibir(item.codigo), 'nome' => item.nome }
  end

  def pela_busca(busca)
    achados = Autonomia::FerramentasProntas::Lista.filtrar(self.class.itens, busca, &:nome)
    raise NaoEncontrado if achados.empty?

    itens = achados.map { |item| { 'codigo' => self.class.exibir(item.codigo), 'nome' => item.nome } }
    Autonomia::FerramentasProntas::Lista.cortar(itens, 'itens', MAXIMO)
  end
end
