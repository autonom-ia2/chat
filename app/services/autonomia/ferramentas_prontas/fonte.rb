# Uma fonte do catálogo (#2858, F0) é UMA ferramenta e UM card: "uma fonte, um card". A fonte com várias consultas (a
# FIPE: marcas, modelos, preço) aparece ao modelo como uma ferramenta só, com o parâmetro `consulta`, e é ele quem
# escolhe a consulta pelo sentido da conversa — nenhuma lista de palavras decide por ele.
#
# `chave`: o que fica gravado em `autonomia_agent_tools.fonte_pronta` e no acesso da conta; nunca muda.
# `slug`: o nome da função que o modelo vê. Começa com `pronta_` para não colidir com as nativas (`Registry`).
# `limite_diario`: o padrão por conta nesta fonte (o acesso da conta pode ter o seu). Decisão do Rodrigo: a proposta
# está no PR da F0.
# `termos`: o que a fonte pede de quem usa (limite, cache), para a revisão de cada lote. Não vai ao modelo.
# `flag`: a flag da fase que trouxe a fonte (a F1 tem a sua), conferida junto com a das prontas; nil nas da F0.
class Autonomia::FerramentasProntas::Fonte
  PARAMETRO_DA_CONSULTA = 'consulta'.freeze

  attr_reader :chave, :slug, :nome, :descricao, :consultas, :limite_diario, :termos, :flag

  def initialize(chave:, slug:, nome:, descricao:, consultas:, limite_diario:, termos:, flag: nil) # rubocop:disable Metrics/ParameterLists
    @flag = flag
    @chave = chave
    @slug = slug
    @nome = nome
    @descricao = descricao
    @consultas = consultas
    @limite_diario = limite_diario
    @termos = termos
  end

  def consulta(nome)
    return consultas.first if consultas.one? && nome.blank?

    consultas.find { |consulta| consulta.nome == nome.to_s }
  end

  def varias_consultas?
    consultas.size > 1
  end

  def provedores
    consultas.flat_map(&:provedores).uniq
  end

  def hosts
    provedores.filter_map(&:host).uniq
  end

  # Os argumentos com cada parâmetro conhecido já normalizado; o que não normaliza fica como veio.
  def normalizar_argumentos(args)
    normalizados = consultas.flat_map(&:parametros).uniq(&:nome).to_h { |parametro| [parametro.nome, parametro.normalizar(args[parametro.nome])] }
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

  def descricao_para_o_modelo(usar_quando)
    partes = [descricao]
    partes << "Consultas: #{consultas.map { |consulta| "#{consulta.nome} (#{consulta.descricao})" }.join('; ')}." if varias_consultas?
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
