# NOME DE DOENÇAS (#2858, F4): o nome da doença pelo código da CID-10 (o "J45" do atestado e da guia) e a busca do
# código pelo nome.
#   - a CID-10 é publicada pelo DATASUS (Ministério da Saúde) como arquivo, sem API aberta: a tabela fica no
#     repositório (`doencas/cid10.rb`), e a fonte é calculada aqui, sem rede e sem cache;
#   - o código é uma letra e 2 dígitos (a categoria, "J45") ou 3 (a subcategoria, "J45.0"), com ou sem o ponto.
# Termos: tabela oficial do DATASUS. Detalhes em `docs/ferramentas-prontas/termos-das-fontes.md`.
module Autonomia::FerramentasProntas::Fontes::Doencas
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  LETRAS = 'A'..'Z'

  module_function

  # "j45.0", " J45 0 ", "J450" -> "J450"; "J4", "45", "JJ45" -> nil.
  def codigo(valor)
    texto = valor.to_s.upcase.delete('. -')
    texto if [3, 4].include?(texto.length) && LETRAS.cover?(texto[0]) && texto[1..].delete(Parametro::DIGITOS).empty?
  end

  CODIGO = Parametro.new(nome: 'codigo', descricao: 'O código CID-10 da doença (ex.: J45 ou J45.0).') { |valor| codigo(valor) }
  BUSCA = Parametro.new(nome: 'busca', descricao: 'Parte do nome da doença (ex.: asma).') { |valor| Parametro.texto_curto(valor) }

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'doencas', slug: 'pronta_doencas', nome: 'Nome de doenças',
    flag: 'agente_ferramentas_prontas_lote2',
    descricao: 'O nome oficial de uma doença pelo código CID-10 (o do atestado ou da guia), e o código pelo nome, na ' \
               'tabela do DATASUS.',
    consultas: [
      Consulta.new(nome: 'codigo', descricao: 'o nome da doença do código; pede codigo', obrigatorios: [CODIGO],
                   provedores: [Cid10], validade: nil, prazo_por_fonte: 1, prazo_total: 1),
      Consulta.new(nome: 'busca', descricao: 'as doenças com o nome; pede busca', obrigatorios: [BUSCA],
                   provedores: [Cid10], validade: nil, prazo_por_fonte: 1, prazo_total: 1)
    ],
    limite_diario: 500,
    termos: 'CID-10 do DATASUS (Ministério da Saúde), guardada no repositório. Sem rede e sem cache.'
  )
end
