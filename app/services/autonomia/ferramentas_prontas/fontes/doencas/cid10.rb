# A CID-10 do DATASUS (categorias e subcategorias, versão 2008) num arquivo do repositório
# (`lib/ferramentas_prontas/doencas.csv`, a origem e os termos ao lado). O código compara sem ponto e em maiúscula
# ("j45.0" e "J450" são o mesmo), e vai ao modelo com o ponto ("J45.0").
class Autonomia::FerramentasProntas::Fontes::Doencas::Cid10 < Autonomia::FerramentasProntas::Fontes::Procedimentos::TabelaLocal
  NOME = 'cid10'.freeze
  ARQUIVO = Rails.root.join('lib/ferramentas_prontas/doencas.csv')

  class << self
    def chave(codigo)
      Autonomia::FerramentasProntas::Fontes::Doencas.codigo(codigo)
    end

    def exibir(codigo)
      normal = chave(codigo)
      normal.length == 4 ? "#{normal[0, 3]}.#{normal[3]}" : normal
    end
  end
end
