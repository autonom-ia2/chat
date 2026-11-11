# EXAMES E PROCEDIMENTOS (#2858, F4): o nome de um procedimento pelo código da TUSS (o "10101012" da guia do plano de
# saúde) e a busca do código pelo nome.
#   - a TUSS (Terminologia Unificada da Saúde Suplementar, tabela 22 do Padrão TISS) é publicada pela ANS como arquivo,
#     sem API: a tabela fica no repositório (`procedimentos/tuss.rb`), e a fonte é calculada aqui, sem rede e sem cache;
#   - o código tem 8 dígitos; o que vier com ponto ou traço ("1.01.01.01-2") vale só pelos dígitos.
# Termos: dado aberto da ANS. Detalhes em `docs/ferramentas-prontas/termos-das-fontes.md`.
module Autonomia::FerramentasProntas::Fontes::Procedimentos
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  CODIGO = Parametro.new(nome: 'codigo', descricao: 'O código TUSS do procedimento, 8 dígitos (ex.: 10101012).',
                         deduza: 'se o cliente disse o nome do exame, use a consulta busca; o código tem 8 dígitos.') do |valor|
    Parametro.digitos(valor, 8)
  end
  BUSCA = Parametro.new(nome: 'busca', descricao: 'Parte do nome do exame ou procedimento (ex.: hemograma).',
                        pergunte: 'o nome do exame ou procedimento') do |valor|
    Parametro.texto_curto(valor)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'procedimentos', slug: 'pronta_procedimentos', nome: 'Exames e procedimentos',
    flag: 'agente_ferramentas_prontas_lote2',
    descricao: 'O nome oficial de um exame ou procedimento pelo código TUSS (o da guia do plano de saúde), e o código ' \
               'pelo nome, na tabela da ANS.',
    consultas: [
      Consulta.new(nome: 'codigo', descricao: 'o nome do procedimento do código; pede codigo', obrigatorios: [CODIGO],
                   provedores: [Tuss], validade: nil, prazo_por_fonte: 1, prazo_total: 1),
      Consulta.new(nome: 'busca', descricao: 'os procedimentos com o nome; pede busca', obrigatorios: [BUSCA],
                   provedores: [Tuss], validade: nil, prazo_por_fonte: 1, prazo_total: 1)
    ],
    limite_diario: 500,
    termos: 'Tabela 22 da TUSS, publicada pela ANS como dado aberto, guardada no repositório. Sem rede e sem cache.'
  )
end
