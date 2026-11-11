# A FIPE PELO NOME (#2858, regra "QI 70" do Rodrigo, 11/11/2026): o cliente diz "Gol 2020", nunca o código da marca nem
# o do modelo. No turno real (e no Experimente), `marca` e `modelo` aceitam o nome; o código sai das listas da própria
# fonte (consultas marcas e modelos, com o cache de 7 dias), pelo `Lista.pelo_nome`: o nome igual, a palavra igual ou o
# começo de palavra, sem acento e sem caixa.
#   - um só: segue com o código, e o agente nem fica sabendo;
#   - mais de um (as versões do Gol): pedido inválido no campo, com os candidatos (código e nome) e a orientação de
#     escolher pelo que o cliente disse ou mostrar a faixa;
#   - nenhum: pedido inválido no campo (marca ou modelo, nunca o código FIPE), com o que fazer.
module Autonomia::FerramentasProntas::Fontes::Fipe::PeloNome
  Lista = Autonomia::FerramentasProntas::Lista
  Falta = Autonomia::FerramentasProntas::Falta

  MAX_CANDIDATOS = 12
  SEM_MARCA = 'Não há marca com esse nome na tabela FIPE. Se o que veio é o modelo, mande em marca a marca dele (Gol é ' \
              'Volkswagen, Onix é Chevrolet); se não dá para saber, pergunte ao cliente a marca. Não invente.'.freeze
  VARIAS_MARCAS = 'Há %<total>s marcas com esse nome. Mande em marca o codigo da que o cliente quis, pelo que ele disse; ' \
                  'se não dá para saber, pergunte a marca.'.freeze
  SEM_MODELO = 'Não há modelo com esse nome nesta marca da tabela FIPE. Confira a marca (Gol é Volkswagen) e o nome do ' \
               'modelo; se não dá para saber, pergunte ao cliente o modelo. Não invente.'.freeze
  VARIOS_MODELOS = 'Há %<total>s versões com esse nome. Escolha a mais provável pelo que o cliente disse e consulte o preco ' \
                   'com o codigo dela em modelo; se nada indica a versão, consulte até 3 versões no mesmo ano, mostre a ' \
                   'faixa de preço e só então pergunte a versão.'.freeze

  module_function

  # O `resolver` das consultas modelos e preco. -> [params com os códigos, nil] ou [nil, a `Falta`].
  def resolver(params, apoio)
    return [params, nil] if params['codigo_fipe']

    marca, falta = codigo_da_marca(params, apoio)
    return [nil, falta] if falta
    return [params.merge('marca' => marca), nil] unless params['modelo']

    modelo, falta = codigo_do_modelo(params.merge('marca' => marca), apoio)
    falta ? [nil, falta] : [params.merge('marca' => marca, 'modelo' => modelo), nil]
  end

  def codigo_da_marca(params, apoio)
    return [params['marca'], nil] if Autonomia::FerramentasProntas::Parametro.codigo(params['marca'])

    lista = Array(apoio.dados('marcas', 'tipo' => params['tipo'])&.dig('marcas'))
    escolher(lista, params['marca'], campo: 'marca', nenhum: SEM_MARCA, varios: VARIAS_MARCAS)
  end

  def codigo_do_modelo(params, apoio)
    return [params['modelo'], nil] if Autonomia::FerramentasProntas::Parametro.codigo(params['modelo'])

    lista = Array(apoio.dados('modelos', params.slice('tipo', 'marca'))&.dig('modelos'))
    escolher(lista, params['modelo'], campo: 'modelo', nenhum: SEM_MODELO, varios: VARIOS_MODELOS)
  end

  # -> [o código, nil] com um achado só; senão [nil, a `Falta`]. Os candidatos vão na ordem de relevância.
  def escolher(lista, nome, campo:, nenhum:, varios:)
    achados = Lista.em_ordem(Lista.pelo_nome(lista, nome) { |item| item['nome'] }, nome) { |item| item['nome'] }
    return [achados.first['codigo'], nil] if achados.one?
    return [nil, Falta.new(campo: campo, orientacao: nenhum)] if achados.empty?

    candidatos = achados.first(MAX_CANDIDATOS).map { |item| item.slice('codigo', 'nome') }
    [nil, Falta.new(campo: campo, candidatos: candidatos, orientacao: format(varios, total: achados.size))]
  end
end
