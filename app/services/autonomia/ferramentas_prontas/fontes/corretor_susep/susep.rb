# A consulta pública de corretores da SUSEP (fonte única: não há outra base oficial dos corretores habilitados).
# O pedido: `tipoPessoa` (PF ou PJ) e `cpfCnpj` ou `nome`, os mesmos campos da tela pública. A resposta é conferida pelo
# `Formato` antes de qualquer dado ir ao modelo.
class Autonomia::FerramentasProntas::Fontes::CorretorSusep::Susep < Autonomia::FerramentasProntas::Provedor
  NOME = 'susep'.freeze
  HOST = 'www2.susep.gov.br'.freeze
  CAMINHO = '/safe/corretoresapig/dadospublicos/pesquisar'.freeze

  def consultar(consulta, params)
    formato = Autonomia::FerramentasProntas::Fontes::CorretorSusep::Formato
    corpo = get(caminho(consulta, params))
    formato.corretores(corpo, documento: params['documento'], nome: params['nome'])
  end

  private

  def caminho(consulta, params)
    corretor = Autonomia::FerramentasProntas::Fontes::CorretorSusep
    if consulta.nome == 'por_documento'
      documento = params.fetch('documento')
      return "#{CAMINHO}?tipoPessoa=#{corretor.pessoa_fisica?(documento) ? 'PF' : 'PJ'}&cpfCnpj=#{codificar(documento)}"
    end

    tipo = params['tipo_pessoa']
    "#{CAMINHO}?#{"tipoPessoa=#{tipo.upcase}&" if tipo}nome=#{codificar(params.fetch('nome'))}"
  end
end
