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

  CODIGO = Parametro.new(nome: 'codigo', descricao: 'O código CID-10 da doença (ex.: J45 ou J45.0).',
                         deduza: 'se o cliente disse o nome da doença, use a consulta busca; o código é letra e dígitos.') do |valor|
    codigo(valor)
  end
  # A tabela tem o nome técnico: quem traduz o que o cliente disse é o modelo (varredura F27, "dor de cabeça").
  BUSCA = Parametro.new(nome: 'busca', descricao: 'Parte do nome da doença, no termo técnico da medicina (ex.: asma; ' \
                                                  'cefaleia, não dor de cabeça).',
                        pergunte: 'o nome da doença') { |valor| Parametro.texto_curto(valor) }

  NAO_ENCONTRADO = 'A tabela CID-10 do DATASUS não tem esse nome ou código. Ela usa o termo técnico: tente de novo com ele ' \
                   '(cefaleia, não dor de cabeça; hipertensão, não pressão alta) antes de dizer ao cliente que não achou. ' \
                   'Código novo da OMS (como o U07.1, da covid-19) pode não estar nesta tabela. Não invente.'.freeze

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'doencas', slug: 'pronta_doencas', nome: 'Nome de doenças',
    flag: 'agente_ferramentas_prontas_lote2',
    descricao: 'O nome oficial de uma doença pelo código CID-10 (o do atestado ou da guia), e o código pelo nome, na ' \
               'tabela do DATASUS.',
    consultas: [
      Consulta.new(nome: 'codigo', descricao: 'o nome da doença do código; pede codigo', obrigatorios: [CODIGO],
                   provedores: [Cid10], validade: nil, prazo_por_fonte: 1, prazo_total: 1, nao_encontrado: NAO_ENCONTRADO),
      Consulta.new(nome: 'busca', descricao: 'as doenças com o nome; pede busca', obrigatorios: [BUSCA],
                   provedores: [Cid10], validade: nil, prazo_por_fonte: 1, prazo_total: 1, nao_encontrado: NAO_ENCONTRADO)
    ],
    limite_diario: 500,
    termos: 'CID-10 do DATASUS (Ministério da Saúde), guardada no repositório. Sem rede e sem cache.'
  )
end
