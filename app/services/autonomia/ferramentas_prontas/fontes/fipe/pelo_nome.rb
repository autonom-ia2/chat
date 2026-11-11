# A FIPE PELO NOME (#2858, regra "QI 70" do Rodrigo, 11/11/2026): o cliente diz "Gol 2020", nunca o código da marca nem
# o do modelo. No turno real (e no Experimente), `marca` e `modelo` aceitam o nome; o código sai das listas da própria
# fonte (consultas marcas e modelos, com o cache de 7 dias), pelo `Lista.pelo_nome`: o nome igual, a palavra igual ou o
# começo de palavra, sem acento e sem caixa.
#   - um só: segue com o código, e o agente nem fica sabendo;
#   - mais de um (as versões do Gol), com o ano: só as versões que têm aquele ano (`MODELOS_DO_ANO`); uma só segue com o
#     código; várias seguem com os códigos de duas de exemplo (`Fipe::MAX_VERSOES`), e vem o preço das duas, sem exigir a
#     escolha (varredura F12); nenhuma: pedido inválido no ano, com o ano que não existe (F13);
#   - mais de um sem o ano: pedido inválido no ano (é ele que estreita), com as versões em candidatos;
#   - nenhum: pedido inválido no campo (marca ou modelo, nunca o código FIPE), com o que fazer.
module Autonomia::FerramentasProntas::Fontes::Fipe::PeloNome
  Lista = Autonomia::FerramentasProntas::Lista
  Falta = Autonomia::FerramentasProntas::Falta
  Fipe = Autonomia::FerramentasProntas::Fontes::Fipe

  MAX_CANDIDATOS = 12
  SEM_MARCA = 'Não há marca com esse nome na tabela FIPE. Se o que veio é o modelo, mande em marca a marca dele (Gol é ' \
              'Volkswagen, Onix é Chevrolet); se não dá para saber, pergunte ao cliente a marca. Não invente.'.freeze
  VARIAS_MARCAS = 'Há %<total>s marcas com esse nome. Mande em marca o codigo da que o cliente quis, pelo que ele disse; ' \
                  'se não dá para saber, pergunte a marca.'.freeze
  SEM_MODELO = 'Não há modelo com esse nome nesta marca da tabela FIPE. Confira a marca (Gol é Volkswagen) e o nome do ' \
               'modelo; se não dá para saber, pergunte ao cliente o modelo. Não invente.'.freeze
  VARIOS_MODELOS = 'Há %<total>s versões com esse nome. Mande o ano-modelo: com ele a plataforma acha as versões daquele ' \
                   'ano e devolve o preço. Se o cliente já disse a versão, mande o codigo dela (de candidatos) em modelo; ' \
                   'senão, pergunte ao cliente o ano-modelo.'.freeze
  ANO_QUE_NAO_EXISTE = 'Nenhuma versão desse modelo tem o ano-modelo %<ano>s na tabela FIPE: esse ano não existe para ele. ' \
                       'Diga isso ao cliente e pergunte o ano certo. Não invente.'.freeze

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

    lista = validos(Array(apoio.dados('marcas', 'tipo' => params['tipo'])&.dig('marcas')))
    escolher(lista, params['marca'], campo: 'marca', nenhum: SEM_MARCA, varios: VARIAS_MARCAS)
  end

  # O modelo que é só número ("208", "500", "3008") é NOME primeiro: o código vale só quando nenhum modelo tem esse
  # nome e ele está na lista da marca (o "500" da Fiat é o 500 Cult, não o código 500 de outro modelo; varredura F11).
  def codigo_do_modelo(params, apoio)
    lista = validos(Array(apoio.dados('modelos', params.slice('tipo', 'marca'))&.dig('modelos')))
    achados = pelo_nome(lista, params['modelo'])
    achados = achados.select { |item| palavra_inteira?(item, params['modelo']) } if do_codigo?(lista, params['modelo'])
    return pelo_codigo(lista, params['modelo']) if achados.empty?
    return [achados.first['codigo'], nil] if achados.one?
    return [nil, varias_versoes(achados)] unless params['ano']

    do_ano(achados, params, apoio)
  end

  # O número que é código da lista ("2", que o agente tirou de candidatos) só vira nome se algum modelo o tem como
  # palavra inteira ("500 Cult"); o começo de palavra ("2" de "2.0") não conta.
  def do_codigo?(lista, modelo)
    lista.any? { |item| item['codigo'] == modelo.to_s }
  end

  def palavra_inteira?(item, modelo)
    Lista.termos(item['nome']).include?(Lista.comparavel(modelo))
  end

  def pelo_codigo(lista, modelo)
    return [modelo, nil] if do_codigo?(lista, modelo)

    [nil, Falta.new(campo: 'modelo', orientacao: SEM_MODELO)]
  end

  def varias_versoes(achados)
    candidatos = achados.first(MAX_CANDIDATOS).map { |item| item.slice('codigo', 'nome') }
    Falta.new(campo: 'ano', candidatos: candidatos, orientacao: format(VARIOS_MODELOS, total: achados.size))
  end

  # As versões que têm o ano. Várias: duas delas de exemplo, a de nome mais curto e a de nome mais longo, e o preço das
  # duas (`Parallelum#versoes`), com o aviso de que o exato depende da versão. Não é o mínimo e o máximo garantidos: isso
  # pediria o preço de cada versão, uma chamada por versão à reserva de teto diário (decisão do Rodrigo, #2906). Os
  # códigos vão com as duas primeiro e as outras depois, só para o texto dizer "há outras" quando há.
  def do_ano(achados, params, apoio)
    do_ano = Array(apoio.dados(Fipe::MODELOS_DO_ANO, params.slice('tipo', 'marca', 'ano'))&.dig('modelos')).pluck('codigo')
    no_ano = achados.select { |item| do_ano.include?(item['codigo']) }
    return [nil, Falta.new(campo: 'ano', orientacao: format(ANO_QUE_NAO_EXISTE, ano: params['ano']))] if no_ano.empty?
    return [no_ano.first['codigo'], nil] if no_ano.one?

    exemplos = no_ano.minmax_by { |item| item['nome'].to_s.length }.pluck('codigo').uniq
    [exemplos + (no_ano.pluck('codigo') - exemplos), nil]
  end

  def pelo_nome(lista, nome)
    Lista.em_ordem(Lista.pelo_nome(lista, nome) { |item| item['nome'] }, nome) { |item| item['nome'] }
  end

  # Só o item com código no formato (dígitos): o código vai ao caminho do pedido seguinte, e veio de fora.
  def validos(lista)
    lista.select { |item| item.is_a?(Hash) && Autonomia::FerramentasProntas::Parametro.codigo(item['codigo']) }
  end

  # -> [o código, nil] com um achado só; senão [nil, a `Falta`]. Os candidatos vão na ordem de relevância.
  def escolher(lista, nome, campo:, nenhum:, varios:)
    achados = pelo_nome(lista, nome)
    return [achados.first['codigo'], nil] if achados.one?
    return [nil, Falta.new(campo: campo, orientacao: nenhum)] if achados.empty?

    candidatos = achados.first(MAX_CANDIDATOS).map { |item| item.slice('codigo', 'nome') }
    [nil, Falta.new(campo: campo, candidatos: candidatos, orientacao: format(varios, total: achados.size))]
  end
end
