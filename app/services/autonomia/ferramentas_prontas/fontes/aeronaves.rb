# AERONAVES (#2858, F5): "a matrícula PR-ABC é de quê?". O que o Registro Aeronáutico Brasileiro (RAB) da ANAC diz da
# aeronave: fabricante, modelo, ano, assentos, situação do registro, validade do certificado de aeronavegabilidade,
# gravames e as EMPRESAS proprietárias e operadoras. Pessoa física nunca aparece: nem nome, nem CPF (só a contagem).
# A base é baixada pela plataforma todo dia (`Bases::Aeronaves`) e a busca é no banco.
module Autonomia::FerramentasProntas::Fontes::Aeronaves
  Parametro = Autonomia::FerramentasProntas::Parametro

  MATRICULA = Parametro.new(nome: 'matricula', descricao: 'A matrícula (as marcas) da aeronave, 5 letras começando por P (ex.: PR-ABC).') do |valor|
    Autonomia::FerramentasProntas::Bases::Aeronaves.matricula(valor)
  end

  PREFIXO = 2

  # "PRXYZ" -> "PR-XYZ": as marcas do Brasil são o prefixo de nacionalidade (2 letras: PP, PR, PS, PT, PU) e mais 3.
  def self.matricula_legivel(matricula)
    "#{matricula[0, PREFIXO]}-#{matricula[PREFIXO..]}"
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'aeronaves', slug: 'pronta_aeronaves', nome: 'Aeronaves', flag: Autonomia::FerramentasProntas::Bases::FLAG,
    descricao: 'O que o registro aeronáutico da ANAC diz de uma aeronave pela matrícula: fabricante, modelo, ano, assentos, ' \
               'se o registro está valendo ou cancelado, a validade do certificado de aeronavegabilidade, os gravames e as ' \
               'empresas donas e operadoras. Dono ou operador pessoa física não é mostrado. atualizado_em diz de quando é.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'aeronave', descricao: 'a aeronave pela matrícula; pede matricula', obrigatorios: [MATRICULA],
        provedores: [Rab], validade: nil, prazo_por_fonte: 1, prazo_total: 1
      )
    ],
    limite_diario: 500,
    termos: 'Registro Aeronáutico Brasileiro (dados abertos da ANAC), baixado pela plataforma todo dia, sem pessoa física.'
  )
end
