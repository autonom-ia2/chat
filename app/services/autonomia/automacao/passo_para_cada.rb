# O passo "para cada item" (#2414 G24, #2771): a IA acha uma lista na conversa (os funcionários novos que o RH mandou) e o
# passo abre um card por item, na etapa escolhida. Uma segunda automação de `card.criado` roda então em cada card.
#
# - A resposta é `{ itens: [ { chave: valor, ... } ] }`, um campo por chave da receita, nulo quando o dado não está escrito.
#   `nome` é obrigatório; `telefone`, quando a receita o pede, é por onde o contato é achado. Os outros campos guiam a
#   IA, e nada é gravado com eles.
# - `maximo` (1 a 50) é o teto técnico: o tamanho de uma resposta da IA, não freio de uso (ver o cabeçalho do AntiLaco).
#   O pedido não leva o teto no schema, porque a resposta que passasse dele seria recusada inteira: a IA ouve o número
#   na instrução, o passo fica com os primeiros e conta o resto em `passou_do_limite`.
# - A lista fica na execução (`<id>.itens`): a nova tentativa depois de um erro passageiro não paga a IA de novo. Os
#   passos seguintes leem `ia.<id>.quantos` (quantos itens) e `ia.<id>.nomes` (os nomes, separados por vírgula).
# - Cada item (ItemDoParaCada) acha ou cria o contato pela mesma linha do Importar contatos e abre o card pelo "criar
#   card" (PassoDeCard), numa raiz própria da cadeia (Cadeia.em_raiz_nova): na raiz da rodada, a automação seguinte
#   rodaria só no 1º card.
# - Age como quem ligou, conferido antes de pagar a IA: a chave de funis, criar card e importar contatos (a pergunta da
#   tela de Contatos). Faltou uma, a automação pausa (`sem_acesso`), como nos outros passos.
# - O registro leva contagens e ids, nunca nome nem telefone: eles ficam no contato e no card, onde o acesso de sempre vale.
class Autonomia::Automacao::PassoParaCada
  include ::Autonomia::Automacao::ComIa

  MODELO = ::Crm::Ai::Config::MODEL_CLASSIFY
  MAXIMO = 50
  # Os valores que o passo deixa para os seguintes: `ia.<id>.<valor>`.
  VALORES = %w[quantos nomes].freeze
  NOME = 'nome'.freeze
  INSTRUCOES = <<~TEXTO.freeze
    Ache na conversa a lista descrita abaixo e devolva um item para cada pessoa ou coisa dela, na ordem em que aparecem.
    Responda só com JSON no schema. Preencha um campo só com o que está escrito: nunca adivinhe nem invente. Devolva null
    no campo que não aparece. Mantenha o idioma original dos valores. Sem a lista na conversa, devolva itens vazio.
  TEXTO

  def self.fala_com_gente?(_passo) = false

  # O ensaio (#2498) só mostra o que procuraria e onde abriria os cards: nenhuma IA é chamada.
  def self.ensaiar(passo)
    { campos: Array(passo['campos']).pluck('chave'), etapa_id: passo['etapa_id'], maximo: passo['maximo'] }
  end

  def self.problemas_ao_salvar(conta, passo, account_user)
    ::Autonomia::Automacao::ProblemasDoParaCada.new(conta, passo, account_user).problemas
  end

  def executar
    negado = impedido || sem_permissao
    return negado if negado

    etapa = @conversa.account.crm_pipeline_stages.find_by(id: @passo['etapa_id'])
    return Resultado.new(tipo: :pulado, motivo: 'etapa_sumiu', dados: {}) if etapa.nil?

    itens, dados = lista
    return itens if itens.is_a?(Resultado)
    return Resultado.new(tipo: :pulado, motivo: 'lista_vazia', dados: dados) if itens.empty?

    guardar_valores(itens)
    abrir_cards(itens, etapa, dados)
  rescue Falha => e
    falhou(e)
  end

  private

  def id = @passo['id']

  def maximo = @passo['maximo'].to_i.clamp(1, MAXIMO)

  def campos = Array(@passo['campos'])

  # A chave de funis e criar card (as do "criar card") e importar contatos, antes de pagar a IA.
  def sem_permissao
    account_user = @acesso.account_user
    motivo = if !::Autonomia::Automacao::RegraDoFunil.chave?(account_user) then 'sem_chave_de_funis'
             elsif !::Autonomia::Automacao::PassoDeCard.cria_card?(account_user) then 'quem_ligou_sem_permissao_card'
             elsif !::CampaignImports::ContactRow.allowed?(account_user) then 'quem_ligou_sem_permissao_importar'
             end
    Resultado.new(tipo: :sem_acesso, motivo: motivo, dados: {}) if motivo
  end

  # [itens, dados do registro]. A lista guardada na execução volta sem nova ida à IA.
  def lista
    guardados = @execucao.textos.to_h["#{id}.itens"]
    return [guardados, { 'quantos' => guardados.size }] if guardados.is_a?(Array)

    estado = leitura
    return nada_para_ler if estado.vazio?

    todos, custo = perguntar_a_lista(estado)
    itens = todos.first(maximo)
    @execucao.guardar_texto!("#{id}.itens", itens)
    [itens, { 'quantos' => itens.size, 'passou_do_limite' => todos.size - itens.size, 'ia' => custo }]
  end

  # [os itens que a IA achou, com nome; o custo].
  def perguntar_a_lista(estado)
    resposta, custo = perguntar(modelo: MODELO, instrucoes: instrucoes, entrada: { conversa: estado.conversa }, schema: schema)
    [Array(resposta['itens']).filter_map { |item| limpo(item) }, custo]
  end

  # Só as chaves da receita, com o texto aparado; o item sem nome não serve (é por ele que o card e o contato nascem).
  def limpo(item)
    valores = campos.to_h { |campo| [campo['chave'], item.to_h[campo['chave']].to_s.strip.presence] }
    valores if valores[NOME]
  end

  def guardar_valores(itens)
    @execucao.guardar_texto!("#{id}.quantos", itens.size.to_s)
    @execucao.guardar_texto!("#{id}.nomes", itens.pluck(NOME).join(', '))
  end

  def abrir_cards(itens, etapa, dados)
    item = ::Autonomia::Automacao::ItemDoParaCada.new(execucao: @execucao, passo: @passo, etapa: etapa, acesso: @acesso,
                                                      solicitante: @conversa.contact)
    itens.each do |valores|
      negado = ::Autonomia::Automacao::Cadeia.em_raiz_nova { item.abrir(valores) }
      return Resultado.new(tipo: :sem_acesso, motivo: negado.motivo, dados: dados.merge(item.contagem)) if negado
    end
    Resultado.new(tipo: :ok, motivo: nil, dados: dados.merge(item.contagem))
  end

  def instrucoes
    lista = campos.map { |campo| "- #{campo['chave']}: #{campo['descricao']}" }
    "#{INSTRUCOES}\nNo máximo #{maximo} itens.\nCada item da lista: #{@passo['descricao']}\nCampos de cada item:\n#{lista.join("\n")}"
  end

  def schema
    propriedades = campos.to_h { |campo| [campo['chave'], { type: %w[string null] }] }
    item = { type: 'object', additionalProperties: false, required: propriedades.keys, properties: propriedades }
    { name: 'automacao_para_cada',
      schema: { type: 'object', additionalProperties: false, required: %w[itens], properties: { itens: { type: 'array', items: item } } } }
  end
end
