# Uma fonte do catálogo (#2858, F0) é UMA ferramenta e UM card: "uma fonte, um card". A fonte com várias consultas (a
# FIPE: marcas, modelos, preço) aparece ao modelo como uma ferramenta só, com o parâmetro `consulta`, e é ele quem
# escolhe a consulta pelo sentido da conversa — nenhuma lista de palavras decide por ele.
#
# `chave`: o que fica gravado em `autonomia_agent_tools.fonte_pronta` e no acesso da conta; nunca muda.
# `slug`: o nome da função que o modelo vê. Começa com `pronta_` para não colidir com as nativas (`Registry`).
# `limite_diario`: o padrão por conta nesta fonte (o acesso da conta pode ter o seu). Decisão do Rodrigo (10/11): 500
# por conta e por fonte, salvo motivo técnico do provedor, documentado na fonte.
# `termos`: o que a fonte pede de quem usa (limite, cache), para a revisão de cada lote. Não vai ao modelo.
# `flag`: a flag da fase que trouxe a fonte (a F1 tem a sua), conferida junto com a das prontas; nil nas da F0.
# `na_vitrine`: falso na fonte que fica no catálogo para uso interno (os agentes de um ramo), sem card avulso: a vitrine,
# o "Incluir", o Experimente e as sugestões não a oferecem; o agente que já a tem continua consultando.
# `consulta_padrao`: a consulta de quando o modelo não diz qual, na fonte que ganhou uma segunda consulta depois (o CEP
# ganhou `por_endereco`): a ferramenta que já estava num agente continua respondendo sem o parâmetro `consulta`.
class Autonomia::FerramentasProntas::Fonte
  PARAMETRO_DA_CONSULTA = 'consulta'.freeze
  # Regra "QI 70" do Rodrigo (11/11/2026), num texto só: vai em toda ferramenta pronta, no turno real e no Experimente
  # (que usa o mesmo `openai_schema`). O que cada fonte resolve sozinha está na descrição dela e das consultas.
  DEDUZIR = 'Dado técnico que dá para tirar da conversa (a cidade em vez da UF, o telefone em vez do DDD, o nome em ' \
            'vez do código) você manda como o cliente disse, e a plataforma resolve. Pergunte ao cliente só o que muda ' \
            'o resultado e não dá para deduzir. Em pedido_invalido, siga a orientacao e consulte de novo.'.freeze
  FORA_DO_FORMATO = '(fora do formato)'.freeze

  attr_reader :chave, :slug, :nome, :descricao, :consultas, :limite_diario, :termos, :flag

  def initialize(chave:, slug:, nome:, descricao:, consultas:, limite_diario:, termos:, flag: nil, consulta_padrao: nil, # rubocop:disable Metrics/ParameterLists
                 na_vitrine: true)
    @consulta_padrao = consulta_padrao
    @flag = flag
    @na_vitrine = na_vitrine
    @chave = chave
    @slug = slug
    @nome = nome
    @descricao = descricao
    @consultas = consultas
    @limite_diario = limite_diario
    @termos = termos
  end

  def na_vitrine?
    @na_vitrine
  end

  def consulta(nome)
    return consultas.first if consultas.one? && nome.blank?
    return consulta(@consulta_padrao) if @consulta_padrao && nome.blank?

    consultas.find { |consulta| consulta.nome == nome.to_s }
  end

  def varias_consultas?
    consultas.size > 1
  end

  # O parâmetro `consulta`, só para a orientação da recusa: a consulta sai do sentido da conversa, nunca do cliente.
  def parametro_da_consulta
    @parametro_da_consulta ||= Autonomia::FerramentasProntas::Parametro.new(
      nome: PARAMETRO_DA_CONSULTA, descricao: 'Qual consulta fazer.',
      deduza: "escolha pelo sentido da conversa uma destas consultas: #{consultas.map(&:nome).join(', ')}."
    )
  end

  def provedores
    consultas.flat_map(&:provedores).uniq
  end

  def hosts
    provedores.filter_map(&:host).uniq
  end

  # Os argumentos com cada parâmetro conhecido já normalizado. O que veio e não normaliza (um telefone inteiro no DDD)
  # vira `FORA_DO_FORMATO`, que nenhum normalizador de parâmetro que vai à fonte aceita: a `Execucao` responde que o
  # pedido não serve, e o valor cru não fica em registro nenhum. Vazio é "não informado" (como no `Parametro`), e o
  # parâmetro local (a busca) nunca recebe o marcador: ele filtraria pelo texto do marcador.
  def normalizar_argumentos(args)
    normalizados = consultas.flat_map(&:parametros).uniq(&:nome).to_h do |parametro|
      [parametro.nome, argumento_normalizado(parametro, args[parametro.nome])]
    end
    args.merge(normalizados.compact)
  end

  # O maior prazo total entre as consultas: o tempo que a consulta em segundo plano espera por esta ferramenta.
  def prazo_maximo
    consultas.map(&:prazo_total).max
  end

  # O schema da função, no formato do `Tool#openai_schema` (`strict: true`: toda propriedade em `required`, e o
  # opcional aceita `null`). `usar_quando`: a frase da conta ("Use quando…"), que diz ao modelo QUANDO usar.
  def openai_schema(slug:, usar_quando:)
    {
      type: 'function', name: slug, description: descricao_para_o_modelo(usar_quando),
      parameters: { type: 'object', properties: propriedades, required: propriedades.keys, additionalProperties: false },
      strict: true
    }
  end

  private

  def argumento_normalizado(parametro, bruto)
    return nil if bruto.nil? || bruto.to_s.strip.empty?

    parametro.normalizar(bruto) || (parametro.local? ? nil : FORA_DO_FORMATO)
  end

  def descricao_para_o_modelo(usar_quando)
    partes = [descricao]
    partes << "Consultas: #{consultas.map { |consulta| "#{consulta.nome} (#{consulta.descricao})" }.join('; ')}." if varias_consultas?
    partes << DEDUZIR
    partes << "Use quando: #{usar_quando.to_s.strip}" if usar_quando.present?
    partes.join(' ')
  end

  # Um parâmetro é obrigatório no schema só se TODA consulta o exige; o resto aceita `null`.
  def propriedades
    @propriedades ||= consultas.flat_map(&:parametros).uniq(&:nome).each_with_object(propriedade_da_consulta) do |parametro, props|
      props[parametro.nome] = parametro.schema(obrigatorio: obrigatorio_em_todas?(parametro.nome))
    end
  end

  def propriedade_da_consulta
    return {} unless varias_consultas?

    { PARAMETRO_DA_CONSULTA => { 'type' => 'string', 'enum' => consultas.map(&:nome), 'description' => 'Qual consulta fazer.' } }
  end

  def obrigatorio_em_todas?(nome)
    consultas.all? { |consulta| consulta.obrigatorios.any? { |parametro| parametro.nome == nome } }
  end
end
