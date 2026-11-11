# PLACAS SOLARES (#2858, F5): "tem geração solar no CEP X?" ou "quantas casas têm placa solar em Sorriso?". Quantos
# sistemas de geração distribuída (micro e minigeração: placas solares, quase todos) estão registrados na ANEEL no CEP
# ou no município, com a potência somada, por tipo e por classe de consumo (residencial, comercial, rural...).
# Nenhum titular é mostrado: a base guarda só a soma. Ela é baixada pela plataforma todo mês (`Bases::GeracaoSolar`).
module Autonomia::FerramentasProntas::Fontes::GeracaoSolar
  Parametro = Autonomia::FerramentasProntas::Parametro

  CEP = Parametro.new(nome: 'cep', descricao: 'O CEP, 8 dígitos.') { |valor| Parametro.digitos(valor, 8) }
  CIDADE = Parametro.new(nome: 'cidade', descricao: 'O nome da cidade (com uf).') { |valor| Parametro.texto_curto(valor) }
  UF = Parametro.new(nome: 'uf', descricao: 'A sigla do estado da cidade.', opcoes: Autonomia::FerramentasProntas::Ufs::SIGLAS.map(&:downcase))

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'geracao_solar', slug: 'pronta_geracao_solar', nome: 'Placas solares', flag: Autonomia::FerramentasProntas::Bases::FLAG,
    descricao: 'Quantos sistemas de geração própria de energia (placas solares, quase todos) a ANEEL tem registrados num CEP ' \
               'ou numa cidade, com a potência somada em kW, por tipo e por classe (residencial, comercial, rural...). Não ' \
               'diz de quem é. Um CEP geral de cidade pequena junta a cidade inteira. atualizado_em diz de quando é.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'cep', descricao: 'os sistemas no CEP; pede cep', obrigatorios: [CEP],
        provedores: [Aneel], validade: nil, prazo_por_fonte: 1, prazo_total: 1
      ),
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'cidade', descricao: 'os sistemas na cidade; pede cidade e uf', obrigatorios: [CIDADE, UF],
        provedores: [Aneel], validade: nil, prazo_por_fonte: 1, prazo_total: 1
      )
    ],
    limite_diario: 500,
    termos: 'Geração distribuída da ANEEL (dados abertos, ODbL), baixada pela plataforma todo mês e guardada só como soma.'
  )
end
