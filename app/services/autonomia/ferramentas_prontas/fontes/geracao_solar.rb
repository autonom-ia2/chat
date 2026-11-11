# PLACAS SOLARES (#2858, F5): "tem geração solar no CEP X?" ou "quantas casas têm placa solar em Sorriso?". Quantos
# sistemas de geração distribuída (micro e minigeração: placas solares, quase todos) estão registrados na ANEEL no CEP
# ou no município, com a potência somada, por classe de consumo (residencial, comercial, rural...) e, quando há mais de
# um, por tipo de geração.
# Nenhum titular é mostrado: a base guarda só a soma. Ela é baixada pela plataforma todo mês (`Bases::GeracaoSolar`).
module Autonomia::FerramentasProntas::Fontes::GeracaoSolar
  Parametro = Autonomia::FerramentasProntas::Parametro

  CEP = Parametro.new(nome: 'cep', descricao: 'O CEP, 8 dígitos.',
                      deduza: 'o CEP tem 8 dígitos; se o cliente disse só a cidade, use a consulta cidade.') { |valor| Parametro.digitos(valor, 8) }
  CIDADE = Parametro.new(nome: 'cidade', descricao: 'O nome da cidade.', pergunte: 'a cidade') { |valor| Parametro.texto_curto(valor) }
  # Regra "QI 70": a UF sai da cidade e também vale pelo nome do estado ("mato grosso").
  UF = Autonomia::FerramentasProntas::Municipios.parametro_uf

  module_function

  # A cidade que o `Municipios` acha (com a UF, ou sem ela quando o nome é único) vai à consulta. Senão, a `Falta` dele:
  # a UF com os estados candidatos (cidade com o mesmo nome em outro estado, ou UF errada), ou a cidade que não existe.
  def regra(params)
    Autonomia::FerramentasProntas::Municipios.falta(params['uf'], params['cidade'])
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'geracao_solar', slug: 'pronta_geracao_solar', nome: 'Placas solares', flag: Autonomia::FerramentasProntas::Bases::FLAG,
    descricao: 'Quantos sistemas de geração própria de energia (placas solares, quase todos) a ANEEL tem registrados num CEP ' \
               'ou numa cidade, com a potência somada em kW, por classe (residencial, comercial, rural...) e, quando há mais ' \
               'de um, por tipo. Não diz de quem é. Um CEP geral de cidade pequena junta a cidade inteira. atualizado_em ' \
               'diz de quando é.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'cep', descricao: 'os sistemas no CEP; pede cep', obrigatorios: [CEP],
        provedores: [Aneel], validade: nil, prazo_por_fonte: 1, prazo_total: 1
      ),
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'cidade', descricao: 'os sistemas na cidade; pede cidade (e uf, se houver outra com o mesmo nome)',
        obrigatorios: [CIDADE], opcionais: [UF], provedores: [Aneel], validade: nil, prazo_por_fonte: 1, prazo_total: 1,
        regra: method(:regra)
      )
    ],
    limite_diario: 500,
    termos: 'Geração distribuída da ANEEL (dados abertos, ODbL), baixada pela plataforma todo mês e guardada só como soma.'
  )
end
