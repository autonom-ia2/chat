# O MODELO PRONTO DE UMA CONVERSA DO CONSTRUTOR (#2881): o modelo do arquivo mais a marca da conversa (as listas como o
# dono as deixou). Só existe para quem pode usar: sem a flag, sem o pacote `seguros`, com o modelo fora do ar ou na Lia,
# `do_thread` devolve nil e a conversa segue como a de qualquer agente `sdr`.
#
# As ferramentas saem sempre filtradas pelo que está liberado para a conta (a flag do Construtor da vitrine e a flag da
# fase de cada fonte): ferramenta de flag desligada some sozinha, sem erro. O que a pessoa já dispensou naquele agente
# (`prontas_dispensadas`) também fica de fora.
class Autonomia::Agents::ModelosDeRamo::Rascunho
  attr_reader :modelo, :marca

  class << self
    # Só a conversa que abriu com modelo tem modelo: uma conversa de ajuste num agente que nasceu de um modelo, não.
    def do_thread(thread)
      marca = thread.state.to_h[Autonomia::Agents::ModelosDeRamo::Marca::CHAVE]
      agente = thread.agent
      return unless marca.is_a?(Hash) && agente&.agent_type != Autonomia::Agents::ModelosDeRamo::AGENTE_DE_COTACAO

      montar(marca_que_vale(marca, agente), account: thread.account, agente: agente)
    end

    # O modelo de um agente que nasceu de um modelo, lido da marca dele: é o que a tela mostra quando reabre o rascunho
    # sem a conversa. nil para quem não nasceu de um modelo, para agente de sistema e para a Lia.
    def do_agente(agent)
      config = agent.config.to_h
      marca = config[Autonomia::Agents::ModelosDeRamo::Marca::CHAVE]
      return unless marca.is_a?(Hash) && config['system_key'].blank?
      return if agent.agent_type == Autonomia::Agents::ModelosDeRamo::AGENTE_DE_COTACAO

      montar(marca, account: agent.account, agente: agent)
    end

    # A marca com que a conversa abre, ou nil (sem modelo: tudo como antes, sem erro).
    #   - conversa sem agente (criação): a cópia do modelo pedido, se a chave existe e a conta pode usar;
    #   - conversa de um rascunho que nasceu de um modelo: a marca do próprio rascunho, com o que o dono já mudou. Um
    #     agente que já existe nunca ganha modelo aqui.
    def marca_de_inicio(account:, agent:, chave:)
      return if agent.nil? && chave.blank?
      return unless Autonomia::Agents::ModelosDeRamo.liberado?(account)
      return marca_do_rascunho(agent, chave) if agent

      modelo = Autonomia::Agents::ModelosDeRamo.buscar(chave)
      modelo && Autonomia::Agents::ModelosDeRamo::Marca.inicial(modelo)
    end

    # O modelo com que a conversa abre (a marca de `marca_de_inicio`, com as ferramentas liberadas para a conta), ou nil.
    def de_inicio(account:, agent:, chave:)
      marca = marca_de_inicio(account: account, agent: agent, chave: chave)
      return if marca.nil?

      new(modelo: Autonomia::Agents::ModelosDeRamo.buscar(marca['chave']), marca: marca, account: account,
          fora: agent&.config.to_h[Autonomia::FerramentasProntas::SugestaoParaAgente::DISPENSADAS])
    end

    private

    # Com o rascunho já criado, a marca que vale é a dele: é nela que os dois caminhos de edição gravam (pela conversa e
    # pelo agente), e é dela que o atendimento lê. A da conversa só vale antes de o rascunho existir.
    def marca_que_vale(da_conversa, agente)
      do_rascunho = agente&.config.to_h[Autonomia::Agents::ModelosDeRamo::Marca::CHAVE]
      do_rascunho.is_a?(Hash) && do_rascunho['chave'] == da_conversa['chave'] ? do_rascunho : da_conversa
    end

    def montar(marca, account:, agente:)
      modelo = Autonomia::Agents::ModelosDeRamo.buscar(marca['chave'])
      return if modelo.nil? || !Autonomia::Agents::ModelosDeRamo.liberado?(account)

      new(modelo: modelo, marca: marca, account: account,
          fora: agente&.config.to_h[Autonomia::FerramentasProntas::SugestaoParaAgente::DISPENSADAS])
    end

    def marca_do_rascunho(agent, chave)
      marca = agent.config.to_h[Autonomia::Agents::ModelosDeRamo::Marca::CHAVE]
      return unless agent.draft? && marca.is_a?(Hash) && agent.agent_type != Autonomia::Agents::ModelosDeRamo::AGENTE_DE_COTACAO
      return if Autonomia::Agents::ModelosDeRamo.buscar(marca['chave']).nil?

      marca if chave.blank? || chave.to_s == marca['chave']
    end
  end

  def initialize(modelo:, marca:, account:, fora: nil)
    @modelo = modelo
    @marca = marca
    @account = account
    @fora = Array(fora).map(&:to_s)
  end

  # O mesmo rascunho com outra marca (a que o dono acabou de editar). Este objeto não muda.
  def com(marca)
    self.class.new(modelo: @modelo, marca: marca, account: @account, fora: @fora)
  end

  # O roteiro que o Construtor recebe: o `.md` do modelo com cada marcador trocado pela lista numerada atual. A troca é
  # por linha inteira igual ao marcador (comparação de texto): um marcador escrito dentro de um item do dono não é lido.
  def roteiro
    @modelo.roteiro.lines(chomp: true).map do |linha|
      lista = Autonomia::Agents::ModelosDeRamo::MARCADORES[linha.strip]
      lista ? Autonomia::Agents::ModelosDeRamo::Marca.numerada(@marca, lista) : linha
    end.join("\n")
  end

  # O "Já vem com": as ferramentas da marca, cada uma com a frase "Use quando" do ramo (ou a que o dono alterou).
  def ferramentas
    liberadas = fontes_liberadas
    Autonomia::Agents::ModelosDeRamo::Marca.ferramentas(@marca).select { |ferramenta| liberadas.include?(ferramenta['fonte']) }
  end

  # O "Também combina": as outras ferramentas grátis do modelo (também a que o dono tirou do "Já vem com", que assim
  # pode voltar), com a frase do ramo.
  def tambem
    escolhidas = Autonomia::Agents::ModelosDeRamo::Marca.ferramentas(@marca).pluck('fonte')
    liberadas = fontes_liberadas - escolhidas
    @modelo.ferramentas.select { |ferramenta| liberadas.include?(ferramenta.fonte) }
           .map { |ferramenta| { 'fonte' => ferramenta.fonte, 'usar_quando' => ferramenta.usar_quando } }
  end

  # Os cartões pagos que o modelo sugere e a conta vê na vitrine. Só sugestão: quem inclui é uma pessoa, na vitrine.
  def premium
    return [] unless Autonomia::FerramentasProntas.vitrine?(@account)

    @modelo.premium.select do |chave|
      Autonomia::FerramentasProntas.na_vitrine?(@account, Autonomia::FerramentasProntas::Catalogo.buscar(chave))
    end
  end

  # As chaves que a Confira e o cartão "pode ganhar" já leem (`ferramentas_sugeridas`, `ferramentas_tambem`).
  def chaves_das_prontas
    { Autonomia::FerramentasProntas::SugestaoParaAgente::CONSTRUTOR => ferramentas.pluck('fonte'),
      Autonomia::FerramentasProntas::SugestaoParaAgente::TAMBEM => tambem.pluck('fonte') }
  end

  # O que a conversa e o agente guardam: a marca e as chaves das ferramentas que saem dela.
  def para_guardar
    { Autonomia::Agents::ModelosDeRamo::Marca::CHAVE => @marca }.merge(chaves_das_prontas)
  end

  # O que a tela recebe. Nada do roteiro: ele é dado nosso e fica oculto, como a instrução.
  def para_tela
    listas = Autonomia::Agents::ModelosDeRamo::Marca
    { 'chave' => @modelo.chave, 'ramo' => @modelo.ramo, 'nome_padrao' => @modelo.nome_padrao,
      'seguradoras_sugeridas' => @modelo.seguradoras_sugeridas,
      'perguntas' => listas.itens(@marca, 'perguntas'), 'documentos' => listas.itens(@marca, 'documentos'),
      'ferramentas' => ferramentas, 'tambem' => tambem, 'premium' => premium, 'teste' => @modelo.teste }
  end

  private

  # As fontes grátis do modelo que a conta tem liberadas e a pessoa não dispensou.
  def fontes_liberadas
    return [] unless Autonomia::FerramentasProntas.construtor?(@account)

    (Autonomia::FerramentasProntas.sugeriveis(@account).map(&:chave) & @modelo.ferramentas.map(&:fonte)) - @fora
  end
end
