# CONFERIR A PESSOA (#2858, F7, Premium): confere quem o cliente diz ser, pelo CPF. Só três respostas: a situação do CPF
# na Receita (na hora, `/ondemand`), o nome e a data de nascimento (`/pessoas`, `basic_data`) e o registro no conselho
# de classe (`class_organization`). Ficam de fora, por desenho: telefone, e-mail e endereço da pessoa, nome da mãe ou
# do pai (parentes), crédito, antecedentes e política. Não há parâmetro nem consulta para nada disso.
module Autonomia::FerramentasProntas::Fontes::Premium::Pessoa
  Premium = Autonomia::FerramentasProntas::Premium
  Extrair = Premium::Extrair
  POR_CPF = ->(params) { "doc{#{params['cpf']}}" }
  DATA = 10

  SITUACAO = lambda do |dado|
    certidao = Array(dado).find { |item| item.is_a?(Hash) }
    situacao = certidao && Extrair.valor(certidao['BaseStatus'])
    situacao && { 'situacao_na_receita' => situacao }
  end

  NOME_E_NASCIMENTO = lambda do |dado|
    nascimento = Extrair.valor(dado['BirthDate'])
    Extrair.sem_vazio({ 'nome' => Extrair.valor(dado['Name']), 'nascimento' => nascimento&.first(DATA) })
  end

  CONSELHO = lambda do |dado|
    lista = Extrair.itens(dado['Memberships'], conselho: 'OrganizationName', uf: 'OrganizationChapter', categoria: 'Category',
                                               registro: 'RegistrationId', situacao: 'Status')
    Extrair.sem_vazio(Extrair.campos(dado, registros_ativos: 'TotalActiveMemberships').merge('registros' => lista))
  end

  # Todas as consultas do card; a `FONTE` oferece só as que a BigDataCorp responde hoje (`Fonte#consultas`). Desde 12/11
  # (#2946), a situação do CPF na Receita está fora: o dataset responde "desligado" na BigDataCorp.
  CONSULTAS = [
    Premium::ConsultaPaga.new(
      nome: 'situacao_cpf', descricao: 'a situação do CPF na Receita Federal', obrigatorios: [Premium::Parametros::CPF],
      dataset: Premium::Dataset.new(nome: 'ondemand_rf_status_person', rota: '/ondemand', resposta: 'OnlineCertificates',
                                    custo: '0.06', preco: '0.09', busca: POR_CPF, extrair: SITUACAO)
    ),
    Premium::ConsultaPaga.new(
      nome: 'nome_e_nascimento', descricao: 'o nome e a data de nascimento do dono do CPF', obrigatorios: [Premium::Parametros::CPF],
      dataset: Premium::Dataset.new(nome: 'basic_data', rota: '/pessoas', resposta: 'BasicData', custo: '0.04', preco: '0.06',
                                    busca: POR_CPF, extrair: NOME_E_NASCIMENTO)
    ),
    Premium::ConsultaPaga.new(
      nome: 'conselho', descricao: 'o registro em conselho de classe (CRM, OAB, CREA e outros)', obrigatorios: [Premium::Parametros::CPF],
      dataset: Premium::Dataset.new(nome: 'class_organization', rota: '/pessoas', resposta: 'Memberships', custo: '0.06',
                                    preco: '0.09', busca: POR_CPF, extrair: CONSELHO)
    )
  ].freeze

  # A descrição não lista o que o card confere: o modelo lê nas consultas da ferramenta, que acompanham `Premium::DESLIGADAS_NA_FONTE`.
  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'conferir_pessoa', slug: 'pronta_conferir_pessoa', nome: 'Conferir a pessoa',
    descricao: 'Consulta paga: confere uma pessoa pelo CPF, só com as consultas desta ferramenta. Não existe consulta de ' \
               'telefone, e-mail, endereço, parentes, crédito ou antecedentes de pessoa física: se pedirem, diga com ' \
               'educação que esse dado não é consultado aqui.',
    consultas: CONSULTAS,
    limite_diario: nil, flag: Premium::FLAG,
    termos: 'BigDataCorp (contrato da plataforma). Dado pessoal: só conferência, nunca contato nem parentes.'
  )
end
