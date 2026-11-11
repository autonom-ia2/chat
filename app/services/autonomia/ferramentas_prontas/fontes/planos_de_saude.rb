# PLANOS DE SAÚDE (#2858, F5): "a operadora X está ativa na ANS?". Pelo CNPJ, pelo número do registro na ANS (6
# dígitos) ou pelo nome. A base é baixada pela plataforma todo dia (`Bases::PlanosDeSaude`) e a busca é no banco.
# Responde a situação (ativa ou cancelada, com a data e o motivo), o tipo de operadora (a modalidade na ANS), a cidade e o registro.
# Termos: dado aberto da ANS. Detalhes em `docs/ferramentas-prontas/termos-das-fontes.md`.
module Autonomia::FerramentasProntas::Fontes::PlanosDeSaude
  Parametro = Autonomia::FerramentasProntas::Parametro

  CNPJ = Parametro.new(nome: 'cnpj', descricao: 'O CNPJ da operadora, com ou sem pontuação.') { |valor| Parametro.cnpj(valor) }
  REGISTRO = Parametro.new(nome: 'registro_ans', descricao: 'O número do registro da operadora na ANS, 6 dígitos (ex.: 326305).') do |valor|
    Parametro.digitos(valor, 6)
  end
  NOME = Parametro.new(nome: 'nome', descricao: 'Parte do nome da operadora (ex.: unimed campinas).') do |valor|
    Parametro.texto_curto(valor)
  end

  module_function

  def regra(params)
    'nome' unless params['cnpj'] || params['registro_ans'] || params['nome']
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'planos_de_saude', slug: 'pronta_planos_de_saude', nome: 'Planos de saúde',
    flag: Autonomia::FerramentasProntas::Bases::FLAG,
    descricao: 'Se uma operadora de plano de saúde está ativa ou cancelada na ANS, pelo CNPJ, pelo registro na ANS ou ' \
               'pelo nome, com o tipo de operadora e a cidade. A base é a cópia oficial da ANS; atualizado_em diz de quando é.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'operadora', descricao: 'a operadora na ANS; pede cnpj, registro_ans ou nome', opcionais: [CNPJ, REGISTRO, NOME],
        provedores: [Ans], validade: nil, prazo_por_fonte: 1, prazo_total: 1, regra: method(:regra)
      )
    ],
    limite_diario: 500,
    termos: 'Cadastro de operadoras da ANS (dados abertos, PDA), baixado pela plataforma todo dia. Sem rede na consulta.'
  )
end
