# A seleção do gatilho recorrente (#2635, G7): os cards ou os contatos da conta em que a automação age. Lista fechada,
# toda no SQL, com os valores como parâmetro (nada interpolado). Começa sempre na conta da automação.
#
# Card: funil, etapa, situação (aberto, ganho, perdido), responsável e "fechado entre N e M dias atrás" (closed_at, no
# índice da conta, funil, situação e fechamento). Contato: tem a etiqueta, não tem a etiqueta, atributo igual a um
# valor. A Receita recusa a seleção vazia: sem condição nenhuma, a automação pegaria a conta inteira por engano.
#
# G22 (exemplo 8, passo 9): contato que pediu card aberto no funil com campo de marcar ainda em branco
# (`solicitante_de`, Autonomia::Automacao::Solicitados), um por empresa. Os cards contados são só os que a pessoa do
# contexto vê; sem contexto (a seleção inteira, quando quem ligou perdeu o acesso), todos.
class Autonomia::Automacao::Tempo::Selecao
  SITUACOES = { 'aberto' => :open, 'ganho' => :won, 'perdido' => :lost }.freeze
  DO_CARD = %w[funil_id etapa_id situacao responsavel_id fechado_entre_dias].freeze
  DO_CONTATO = %w[etiqueta sem_etiqueta atributo solicitante_de].freeze

  def initialize(conta, gatilho, agora: Time.current)
    @conta = conta
    @card = ::Autonomia::Automacao::Gatilhos.do_card?(gatilho['tipo'])
    @selecao = gatilho['selecao'].to_h
    @agora = agora
  end

  # As condições que a pessoa pôs; vazio = a Receita recusa.
  def condicoes = @selecao.slice(*(@card ? DO_CARD : DO_CONTATO)).compact

  # Sem condição nenhuma, ninguém: a seleção vazia nunca vira a conta inteira (a Receita também recusa ao salvar).
  def escopo
    return (@card ? ::Crm::Card : ::Contact).none if condicoes.empty?

    @card ? do_card : do_contato
  end

  # A seleção só entre os que a pessoa do contexto vê: quem ligou, na execução; quem pede, no ensaio. O mesmo SQL nos
  # dois, para o número do ensaio ser o que a execução pega. O card, pelo escopo da política do card; o contato, só com
  # a base de contatos aberta para ela (nil sem ela). Registro que a pessoa não vê fica fora, sem pausar a automação.
  # `pergunta`: index? para quem vê (o ensaio); update? para quem age (a execução, a mesma do Acesso#alcanca?).
  def escopo_para(contexto, pergunta: :index?)
    return escopo.where(id: cards_de(contexto).select(:id)) if @card
    return unless ContactPolicy.new(contexto, ::Contact).public_send(pergunta)

    solicitante_de? ? do_contato(cards_de(contexto)) : escopo
  end

  # A seleção da execução: só o que quem ligou vê. Sem acesso para agir (saiu da conta, perdeu a permissão), vai a
  # seleção inteira: a Partida pausa a automação no primeiro alvo, com o motivo, em vez de ela parar calada.
  def de_quem_ligou(acesso)
    return escopo if acesso.motivo

    escopo_para(acesso.contexto, pergunta: :update?) || escopo.none
  end

  # Quantos a seleção pegaria agora, para quem pede (parecer do Funções: contar a conta inteira viraria oráculo de
  # "quantos contatos têm o atributo X"). Só o número, nunca a lista.
  def quantos_para(contexto) = escopo_para(contexto)&.count

  private

  def do_card
    escopo = ::Crm::Card.where(account_id: @conta.id)
    escopo = escopo.where(pipeline_id: @selecao['funil_id']) if @selecao['funil_id']
    escopo = escopo.where(stage_id: @selecao['etapa_id']) if @selecao['etapa_id']
    escopo = escopo.where(status: SITUACOES.fetch(@selecao['situacao'])) if @selecao['situacao']
    escopo = escopo.where(owner_id: @selecao['responsavel_id']) if @selecao['responsavel_id']
    fechado_entre(escopo)
  end

  def fechado_entre(escopo)
    faixa = @selecao['fechado_entre_dias']
    return escopo unless faixa

    escopo.where(closed_at: (@agora - faixa['ate'].to_i.days)..(@agora - faixa['de'].to_i.days))
  end

  def do_contato(cards_visiveis = nil)
    escopo = ::Contact.where(account_id: @conta.id)
    escopo = escopo.where(id: solicitantes(cards_visiveis)) if solicitante_de?
    escopo = escopo.tagged_with(@selecao['etiqueta'], on: :labels) if @selecao['etiqueta']
    escopo = escopo.where.not(id: com_etiqueta(@selecao['sem_etiqueta'])) if @selecao['sem_etiqueta']
    atributo = @selecao['atributo']
    atributo ? escopo.where('contacts.custom_attributes ->> ? = ?', atributo['chave'], atributo['valor'].to_s) : escopo
  end

  def cards_de(contexto) = Pundit.policy_scope!(contexto, ::Crm::Card)

  def solicitante_de? = condicoes.key?('solicitante_de')

  def solicitantes(cards_visiveis)
    ::Autonomia::Automacao::Solicitados.new(@conta, @selecao['solicitante_de'], visiveis: cards_visiveis).representantes
  end

  def com_etiqueta(etiqueta) = ::Contact.where(account_id: @conta.id).tagged_with(etiqueta, on: :labels).select(:id)
end
