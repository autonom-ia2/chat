# O passo "extrair" (#2500 F7): a IA tira dados da conversa (placa, data, valor) e o passo grava onde quem montou
# mandou: atributo do contato ou da conversa, o nome do contato ou o da empresa. E-mail e telefone não são destino
# (D4 A).
#
# - A resposta tem um campo por chave, do tipo do atributo da conta: número para número, moeda e porcentagem, sim/não
#   para caixa de seleção, uma das opções para lista, data no formato AAAA-MM-DD. Nulo quando o dado não está escrito.
# - Para a data relativa ("bati o carro ontem"), a IA recebe a data de hoje e a de cada mensagem, no fuso da conta.
# - Só preenche: o valor que já existia fica, porque o texto é de terceiros. Com `trocar: true`, o novo entra.
# - Grava pela porta da frente, como quem ligou (PassoDeAcao): a plataforma confere a permissão, e quem não pode
#   gravar pausa a automação, como na ação.
# - O registro diz as chaves gravadas, as ausentes e as que já tinham valor. Nunca os valores: eles ficam no contato e
#   na conversa, onde o acesso de sempre vale.
class Autonomia::Automacao::PassoDeExtrair
  include ::Autonomia::Automacao::ComIa

  MODELO = ::Crm::Ai::Config::MODEL_CLASSIFY
  NUMERICOS = %w[number currency percent].freeze
  MODELOS = ::Autonomia::Automacao::Valores::MODELOS
  INSTRUCOES = <<~TEXTO.freeze
    Tire da conversa os dados pedidos. Responda só com JSON no schema, um campo por chave.
    Preencha um campo só com o que está escrito na conversa: nunca adivinhe nem invente. Devolva null quando o dado não aparece.
    Mantenha o idioma original do valor. Data no formato AAAA-MM-DD.
    Cada mensagem começa pela data e hora em que foi escrita, no fuso da conta, e "hoje" diz a data de agora.
    Data relativa ("ontem", "sexta passada") conta a partir da data da mensagem em que aparece.
  TEXTO

  def self.fala_com_gente?(_passo) = false

  def executar
    negado = impedido
    return negado if negado

    fuso = fuso_da_conta
    estado = leitura(fuso: fuso)
    return nada_para_ler if estado.vazio?

    entrada = { hoje: Time.current.in_time_zone(fuso).to_date.iso8601, conversa: estado.conversa }
    resposta, custo = perguntar(modelo: MODELO, instrucoes: instrucoes, entrada: entrada, schema: schema)
    gravar(achados(resposta), custo)
  rescue Falha => e
    falhou(e)
  end

  private

  def campos = Array(@passo['campos'])

  def trocar? = @passo['trocar'] == true

  # { campo => valor } só dos que a IA achou e têm onde gravar.
  def achados(resposta)
    campos.each_with_object({}) do |campo, lista|
      valor = pronto(campo, resposta[campo['chave']])
      lista[campo] = valor unless valor.nil? || dono(campo).nil?
    end
  end

  # O registro diz, campo a campo, o que gravou e o que a plataforma recusou: na falha parcial (o contato gravou, a
  # conversa não), `gravados` leva só o que voltou certo e `falhou`, o resto.
  def gravar(achados, custo)
    ja_tinha, novos = achados.keys.partition { |campo| !trocar? && !vazio?(atual(campo)) }
    gravados, falha, recusados = achados.empty? ? [[], nil, []] : escrever(novos.index_with { |campo| achados[campo] })
    dados = { 'campos' => do_registro(gravados, recusados, ausentes: campos - achados.keys, ja_tinha: ja_tinha), 'ia' => custo }
    return Resultado.new(tipo: :pulado, motivo: 'dado_ausente', dados: dados) if achados.empty?

    falha ? Resultado.new(tipo: falha.tipo, motivo: falha.motivo, dados: dados) : Resultado.new(tipo: :ok, dados: dados)
  end

  # [chaves gravadas, o primeiro resultado que não deu certo (ou nil), chaves que não foram gravadas]. Uma ação por
  # lugar (contato, conversa, empresa); depois da primeira recusa, as seguintes não rodam.
  def escrever(valores)
    gravados = []
    lista = pedidos(valores)
    lista.each_with_index do |(acao, id, corpo, chaves_do_pedido), indice|
      resultado = ::Autonomia::Automacao::PassoDeAcao.new(execucao: @execucao, passo: passo_da_acao(acao, id, corpo), valores: nil,
                                                          acesso: @acesso).executar
      return [gravados, resultado, lista.drop(indice).flat_map(&:last)] unless resultado.tipo == :ok

      gravados.concat(chaves_do_pedido)
    end
    [gravados, nil, []]
  end

  def passo_da_acao(acao, id, corpo)
    { 'id' => @passo['id'], 'acao' => acao, 'descricao' => I18n.t('autonomia.automacao.ia.gravar'), 'caminho' => { 'id' => id }, 'corpo' => corpo }
  end

  # [ação, id, corpo, chaves dos campos] por lugar.
  def pedidos(valores)
    por_lugar = valores.group_by { |campo, _valor| lugar(campo) }.transform_values(&:to_h)
    [do_contato(por_lugar[:contato]), da_conversa(por_lugar[:conversa]), da_empresa(por_lugar[:empresa])].compact
  end

  def do_contato(valores)
    return unless valores

    corpo = valores.each_with_object({}) do |(campo, valor), lista|
      next lista['name'] = valor if campo['destino'] == 'contato.nome'

      (lista['custom_attributes'] ||= {})[chave_do_atributo(campo)] = valor
    end
    ['PATCH contacts/:id', @conversa.contact_id, corpo, chaves(valores.keys)]
  end

  def da_conversa(valores)
    return unless valores

    atributos = valores.transform_keys { |campo| chave_do_atributo(campo) }
    ['POST conversations/:id/custom_attributes', @conversa.display_id, { 'custom_attributes' => atributos, 'merge' => true }, chaves(valores.keys)]
  end

  def da_empresa(valores)
    ['PATCH companies/:id', @conversa.contact.company_id, { 'name' => valores.values.last }, chaves(valores.keys)] if valores
  end

  def lugar(campo)
    destino = campo['destino']
    return :empresa if destino == 'empresa.nome'

    destino.start_with?('conversa.') ? :conversa : :contato
  end

  # Onde o campo grava; nil quando não há (contato sem empresa).
  def dono(campo)
    case lugar(campo)
    when :empresa then @conversa.contact&.company
    when :conversa then @conversa
    else @conversa.contact
    end
  end

  def chave_do_atributo(campo) = ::Autonomia::Automacao::Valores.atributo(campo['destino'])&.last

  # O valor de agora. O nome que a plataforma pôs por falta de outro (o e-mail, o telefone) conta como vazio, como no
  # Aplicador do Decisor.
  def atual(campo)
    case campo['destino']
    when 'contato.nome' then @conversa.contact.name unless ::Autonomia::Decisores::Aplicador.nome_provisorio?(@conversa.contact)
    when 'empresa.nome' then dono(campo)&.name
    else dono(campo)&.custom_attributes.to_h[chave_do_atributo(campo)]
    end
  end

  def vazio?(valor) = valor.nil? || (valor.respond_to?(:empty?) && valor.empty?)

  def chaves(lista) = lista.pluck('chave')

  def do_registro(gravados, recusados, ausentes:, ja_tinha:)
    registro = { 'gravados' => na_ordem(gravados), 'ausentes' => chaves(ausentes), 'ja_tinha' => chaves(ja_tinha) }
    recusados.any? ? registro.merge('falhou' => na_ordem(recusados)) : registro
  end

  # As chaves na ordem dos campos da receita.
  def na_ordem(lista) = chaves(campos) & lista

  # O valor pronto para gravar, ou nil. Data que não é data conta como não achada.
  def pronto(campo, valor)
    return valor unless valor.is_a?(String)

    texto = valor.strip.presence
    return texto unless texto && tipo(campo) == 'date'

    Date.iso8601(texto).iso8601
  rescue Date::Error
    nil
  end

  def instrucoes
    lista = campos.map { |campo| "- #{campo['chave']}: #{campo['descricao']}" }
    "#{INSTRUCOES}\nDados:\n#{lista.join("\n")}"
  end

  def schema
    propriedades = campos.to_h { |campo| [campo['chave'], propriedade(campo)] }
    { name: 'automacao_extrair',
      schema: { type: 'object', additionalProperties: false, required: propriedades.keys, properties: propriedades } }
  end

  def propriedade(campo)
    tipo = tipo(campo)
    return { type: %w[number null] } if NUMERICOS.include?(tipo)
    return { type: %w[boolean null] } if tipo == 'checkbox'
    return { type: %w[string null], enum: [*Array(definicao(campo)&.attribute_values), nil] } if tipo == 'list'

    { type: %w[string null] }
  end

  def tipo(campo) = definicao(campo)&.attribute_display_type

  def definicao(campo)
    base, chave = ::Autonomia::Automacao::Valores.atributo(campo['destino'])
    return unless base

    definicoes.find { |item| item.attribute_model == MODELOS.fetch(base) && item.attribute_key == chave }
  end

  def definicoes
    chaves = campos.filter_map { |campo| ::Autonomia::Automacao::Valores.atributo(campo['destino'])&.last }
    @definicoes ||= @conversa.account.custom_attribute_definitions.where(attribute_key: chaves).to_a
  end
end
