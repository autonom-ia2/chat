# O passo "extrair" (#2500 F7): a IA tira dados da conversa (placa, data, valor) e o passo grava onde quem montou
# mandou: atributo do contato, da conversa ou do card (G70, termo F7: "grava no contato ou no card"), o nome do contato
# ou o da empresa. E-mail e telefone não são destino (D4 A).
#
# - G70 (decisão 20 do Rodrigo, 10/11, "IA só anota campos"): grava no card que esta execução criou antes (o passo
#   "criar card", RegistroCriado: o card novo não vira o assunto da conversa, PassoDeCard); senão, no alvo (gatilho de
#   card, ou o ramo do "em outro registro" num card); senão, numa conversa, no card dela que quem ligou vê
#   (CardDaConversa.ler). Só campo personalizado, nunca o valor protegido (decisão 9) nem o que guarda gente: o tipo é
#   conferido de novo aqui, porque muda depois de salvo (Receita::CAMPOS_DE_GENTE). Sem card, ou com o campo que virou
#   gente, o campo não tem onde gravar e conta como ausente. A gravação é o PATCH do card, como quem ligou.
#
# - A resposta tem um campo por chave, do tipo do atributo da conta: número para número, moeda e porcentagem, sim/não
#   para caixa de seleção, uma das opções para lista, data no formato AAAA-MM-DD. Nulo quando o dado não está escrito.
# - Para a data relativa ("bati o carro ontem"), a IA recebe a data de hoje e a de cada mensagem, no fuso da conta.
# - Só preenche: o valor que já existia fica, porque o texto é de terceiros. Com `trocar: true`, o novo entra.
# - Grava pela porta da frente, como quem ligou (PassoDeAcao): a plataforma confere a permissão, e quem não pode
#   gravar pausa a automação, como na ação.
# - O registro diz as chaves gravadas, as ausentes e as que já tinham valor. Nunca os valores: eles ficam no contato e
#   na conversa, onde o acesso de sempre vale.
# - G68 (#2864, exemplo 19, passo 3): lê também as conversas da própria execução, como o "resumir" (G42,
#   EnviosDaExecucao): a resposta do e-mail chega na conversa do e-mail, não na do alvo. As mesmas regras: só a conversa
#   que quem ligou vê e que todos que veem a do alvo também veem; das outras, só mensagens (nunca nota privada) e nunca
#   valor protegido (decisão 9). Lá, cada mensagem também vai com a data e a hora, no fuso da conta.
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
    Em other_conversations estão as respostas do cliente em outras conversas desta automação (como o e-mail): valem como a conversa.
    Em automation_sends está o que esta automação mandou ao cliente: nunca tire dado dali.
  TEXTO

  def self.fala_com_gente?(_passo) = false

  # O ensaio (#2498) só mostra o que procuraria e onde gravaria: nenhuma IA é chamada.
  def self.ensaiar(passo)
    { campos: Array(passo['campos']).map { |campo| { chave: campo['chave'], destino: campo['destino'] } } }
  end

  def executar
    negado = impedido
    return negado if negado

    fuso = fuso_da_conta
    estado = leitura_da_execucao(fuso)
    return nada_para_ler if estado.vazio?
    return sem_onde_gravar if campos.none? { |campo| dono(campo) }

    entrada = { hoje: Time.current.in_time_zone(fuso).to_date.iso8601, conversa: estado.conversa }
    resposta, custo = perguntar(modelo: MODELO, instrucoes: instrucoes, entrada: entrada, schema: schema)
    gravar(achados(resposta), custo)
  rescue Falha => e
    falhou(e)
  end

  private

  def campos = Array(@passo['campos'])

  # G68: a leitura do passo com as conversas da execução (EnviosDaExecucao), como no "resumir".
  def leitura_da_execucao(fuso)
    @envios = ::Autonomia::Automacao::EnviosDaExecucao.new(execucao: @execucao, conversa: @conversa, leituras: @passo['le'], fuso: fuso)
    ::Autonomia::Automacao::LeituraDaExecucao.new(leitura(fuso: fuso), @envios)
  end

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
    dados = { 'campos' => do_registro(gravados, recusados, ausentes: campos - achados.keys, ja_tinha: ja_tinha), 'ia' => custo,
              'conversas_fora' => @envios.fora.presence }.compact
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
    [do_contato(por_lugar[:contato]), da_conversa(por_lugar[:conversa]), do_card(por_lugar[:card]), da_empresa(por_lugar[:empresa])].compact
  end

  def do_card(valores)
    return unless valores

    atributos = valores.transform_keys { |campo| chave_do_atributo(campo) }
    ['PATCH crm/cards/:id', card.id, { 'card' => { 'custom_attributes' => atributos } }, chaves(valores.keys)]
  end

  # G70: o card que esta execução criou, senão o alvo, senão o da conversa que quem ligou vê; nil sem card.
  def card
    return @card if defined?(@card)

    @card = card_criado || (@alvo if @alvo.is_a?(::Crm::Card)) ||
            ::Autonomia::Automacao::CardDaConversa.editavel(@conversa, quem_ligou_na_conta)
  end

  # Nenhum campo tem onde gravar (conversa sem card, contato sem empresa): pula sem pagar a IA.
  def sem_onde_gravar
    dados = { 'campos' => do_registro([], [], ausentes: campos, ja_tinha: []) }
    Resultado.new(tipo: :pulado, motivo: 'dado_ausente', dados: dados)
  end

  # O último card que um passo desta execução criou e que ainda existe (RegistroCriado), ou nil.
  def card_criado
    criados = @execucao.registros.where(resultado: 'ok').where("dados -> 'criado' ->> 'tipo' = ?", ::Autonomia::Automacao::RegistroCriado::CARD)
    id = criados.reorder(id: :desc).pick(Arel.sql("dados -> 'criado' ->> 'id'"))
    id && @execucao.account.crm_cards.find_by(id: id)
  end

  # O campo do card que ainda existe e não guarda gente (o tipo muda depois de salvo).
  def campo_do_card?(campo)
    tipo = tipo(campo)
    tipo.present? && ::Autonomia::Automacao::Receita::CAMPOS_DE_GENTE.exclude?(tipo)
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
    return :card if ::Autonomia::Automacao::CardDaConversa.destino_do_card?(destino)

    destino.start_with?('conversa.') ? :conversa : :contato
  end

  # Onde o campo grava; nil quando não há (contato sem empresa).
  def dono(campo)
    case lugar(campo)
    when :empresa then @conversa.contact&.company
    when :conversa then @conversa
    when :card then card if campo_do_card?(campo)
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
