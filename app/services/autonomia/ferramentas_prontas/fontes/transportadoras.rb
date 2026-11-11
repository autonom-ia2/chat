# TRANSPORTADORAS (#2858, F5): "o registro na ANTT (RNTRC) está ativo?". Pelo número do RNTRC, pelo CNPJ ou pelo nome da empresa,
# o que o Registro Nacional de Transportadores Rodoviários de Cargas diz: a situação (ativo ou pendente), a categoria
# (empresa, cooperativa ou autônomo), o município e as datas. A ANTT só publica os registros ativos e pendentes: quem
# não está na base não tem RNTRC valendo (ou ainda não entrou na publicação do mês). Do autônomo (pessoa física), nem
# nome nem CPF. A base é baixada pela plataforma todo mês (`Bases::Transportadoras`).
module Autonomia::FerramentasProntas::Fontes::Transportadoras
  Parametro = Autonomia::FerramentasProntas::Parametro

  RNTRC = Parametro.new(nome: 'rntrc', descricao: 'O número do RNTRC, até 9 dígitos (ex.: 050085788).',
                        deduza: 'se o cliente disse o CNPJ ou o nome da transportadora, deixe o RNTRC vazio e mande um deles; o ' \
                                'RNTRC tem até 9 dígitos; senão, pergunte ao cliente o nome da transportadora.') do |valor|
    texto = valor.to_s.strip
    Autonomia::FerramentasProntas::Bases::Transportadoras.rntrc(texto) if texto.delete('0-9 .-').empty?
  end
  CNPJ = Parametro.new(nome: 'cnpj', descricao: 'O CNPJ da transportadora, com ou sem pontuação.',
                       deduza: 'se o cliente disse o nome da transportadora, deixe o CNPJ vazio e mande o nome; senão, pergunte ' \
                               'a ele o CNPJ completo (14 posições) ou o nome da transportadora.') { |valor| Parametro.cnpj(valor) }
  NOME = Parametro.new(nome: 'nome', descricao: 'Parte do nome da empresa ou cooperativa (ex.: transportes exemplo).',
                       pergunte: 'o nome da transportadora (ou o CNPJ ou o número do RNTRC dela)') do |valor|
    Parametro.texto_curto(valor)
  end

  module_function

  def regra(params)
    'nome' unless params['rntrc'] || params['cnpj'] || params['nome']
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'transportadoras', slug: 'pronta_transportadoras', nome: 'Transportadoras', flag: Autonomia::FerramentasProntas::Bases::FLAG,
    descricao: 'Se o registro de transportador de carga na ANTT (RNTRC) está ativo ou pendente, pelo número do RNTRC, pelo ' \
               'CNPJ ou pelo nome da empresa, com a categoria (empresa, cooperativa ou autônomo), o município e as datas. ' \
               'A ANTT publica só os ativos e pendentes: sem registro aqui, não há RNTRC valendo na publicação do mês. ' \
               'Do autônomo não vêm nome nem CPF. atualizado_em diz de quando é a base.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'registro', descricao: 'o registro na ANTT; pede rntrc, cnpj ou nome', opcionais: [RNTRC, CNPJ, NOME],
        provedores: [Antt], validade: nil, prazo_por_fonte: 1, prazo_total: 1, regra: method(:regra)
      )
    ],
    limite_diario: 500,
    termos: 'RNTRC da ANTT (dados abertos, Creative Commons Atribuição), baixado pela plataforma todo mês, sem pessoa física.'
  )
end
