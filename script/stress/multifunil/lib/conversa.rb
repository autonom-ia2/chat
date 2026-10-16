# Roda uma conversa sintética do começo ao fim: monta a conta, os cards de antes, o histórico, a presença dos atendentes
# e as mensagens do cliente, deixando a bomba executar o que o sistema agenda depois de cada uma. Devolve o retrato do
# que as duas IAs decidiram (por mensagem) e o estado final, para a conferência.
#
# Outro canal (ex.: e-mail): `outro_canal: { caixa:, vincular: [refs] }` abre uma segunda conversa do MESMO contato na
# caixa indicada e a liga aos cards de `vincular` (como o vínculo de outro canal do CRM). Linhas com `canal: <caixa>`
# vão para essa conversa; sem `canal`, para a principal.
class Stress::Conversa
  PASSO_DO_HISTORICO = 40 # segundos entre as mensagens do histórico
  PAPEIS = { 'cliente' => :incoming, 'robo' => :outgoing, 'atendente' => :outgoing }.freeze

  attr_reader :mundo, :conversation, :refs

  def initialize(dados:, modelo:, relogio:, bomba:)
    @dados = dados
    @modelo = modelo
    @relogio = relogio
    @bomba = bomba
    @refs = {}
    @turnos = []
    @conversas = {}
  end

  def rodar
    @mundo = Stress::Mundo.new(modelo: @modelo, nome: @dados['id']).montar
    criar_conversas
    Array(@dados['historico']).each { |linha| falar(linha) }
    Array(@dados['cards']).each { |card| criar_card(card) }
    focar_card_inicial
    vincular_outro_canal
    marcar_presenca
    @bomba.limpar!
    @bomba.latencia!
    rodar_turnos
    { turnos: @turnos, final: Stress::Retrato.new(self).final }
  end

  private

  def criar_conversas
    @contato = Contact.create!(account: @mundo.account, name: @dados['cliente'] || 'Cliente Teste',
                               email: (@dados['outro_canal'] ? "#{@dados['id'].downcase}.#{@mundo.account.id}@cliente.invalid" : nil))
    @mundo.caixas.each do |chave, caixa|
      next unless chave == 'principal' || @dados.dig('outro_canal', 'caixa') == chave

      @conversas[chave] = abrir_conversa(caixa)
    end
    @conversation = @conversas.fetch('principal')
  end

  def abrir_conversa(caixa)
    contact_inbox = ContactInbox.create!(contact: @contato, inbox: caixa, source_id: SecureRandom.uuid)
    Conversation.create!(account: @mundo.account, inbox: caixa, contact: @contato, contact_inbox: contact_inbox)
  end

  def falar(linha)
    @relogio.avancar(linha['depois_s'] || PASSO_DO_HISTORICO)
    papel = linha['de'] || 'cliente'
    conversa = @conversas.fetch(linha['canal'] || 'principal')
    atributos = { account: @mundo.account, inbox: conversa.inbox, message_type: PAPEIS.fetch(papel), content: linha['texto'] }
    atributos[:sender] = remetente(papel)
    conversa.messages.create!(atributos)
  end

  def vincular_outro_canal
    outro = @dados['outro_canal']
    return if outro.nil?

    conversa = @conversas.fetch(outro['caixa'])
    Array(outro['vincular']).each do |ref|
      Crm::CardConversation.find_or_create_by!(account: @mundo.account, card: @refs.fetch(ref), conversation: conversa)
    end
  end

  def remetente(papel)
    case papel
    when 'cliente' then @conversation.contact
    when 'atendente' then @mundo.pessoas.values.first
    when 'robo' then robo
    end
  end

  def robo
    @robo ||= AgentBot.create!(account: @mundo.account, name: 'Assistente Virtual')
  end

  # Card de antes do teste, já com assunto (nome dado) e na etapa pedida. `foco: true` é o assunto atual.
  def criar_card(dados)
    pipeline = @mundo.funis.fetch(dados['funil'])
    stage = @mundo.etapa(dados['funil'], dados['etapa'])
    card = Crm::Cards::Creator.new(account: @mundo.account, user: nil, conversation: @conversation,
                                   params: { pipeline_id: pipeline.id, stage_id: stage.id, title: dados['titulo'],
                                             value_cents: dados['valor_cents'],
                                             metadata: { 'subject' => { 'source' => 'ai', 'named_at' => Time.current.iso8601 } } }).perform
    fechar(card, dados) if dados['status'].present?
    @relogio.avancar(1)
    @refs[dados['ref']] = card
  end

  # Depois de criar todos: o card criado por último ficaria em foco (o vínculo nasce com a hora da criação). O foco
  # inicial é o marcado com `foco: true`, como se a IA o tivesse escolhido (sem pessoa: a IA pode trocá-lo).
  def focar_card_inicial
    Crm::CardConversation.where(conversation_id: @conversation.id).update_all(focused_at: nil, focused_by_id: nil) # rubocop:disable Rails/SkipsModelValidations
    dados = Array(@dados['cards']).find { |card| card['foco'] }
    return if dados.nil?

    vinculo = Crm::CardConversation.find_or_create_by!(account: @mundo.account, card: @refs.fetch(dados['ref']), conversation: @conversation)
    vinculo.update!(focused_at: Time.current)
    @relogio.avancar(1)
  end

  def fechar(card, dados)
    fechado = Time.current - dados.fetch('fechado_ha_dias', 0).to_i.days
    card.update_columns(status: Crm::Card.statuses.fetch(dados['status']), closed_at: fechado) # rubocop:disable Rails/SkipsModelValidations
  end

  # O relógio virtual anda minutos ou dias, e a presença por batimento vence em 20 s. Online aqui é "sempre online"
  # (auto_offline desligado, disponível): o mesmo que o atendente que marca ficar online na conta.
  def marcar_presenca
    Array(@dados['online']).each do |chave|
      user = @mundo.pessoas.fetch(chave)
      AccountUser.find_by!(account_id: @mundo.account.id, user_id: user.id).update!(auto_offline: false, availability: :online)
      OnlineStatusTracker.set_status(@mundo.account.id, user.id, 'online')
    end
  end

  def rodar_turnos
    pendentes = []
    Array(@dados['turnos']).each do |turno|
      pendentes << falar(turno.merge('de' => turno['de'] || 'cliente'))
      # Fala do robô ou do atendente no meio da conversa não é observada sozinha: vai junto com a próxima do cliente.
      next if turno['rajada'] || turno.fetch('de', 'cliente') != 'cliente'

      @turnos << observar(pendentes)
      pendentes = []
    end
    @turnos << observar(pendentes) if pendentes.any?
  end

  def observar(mensagens)
    antes = Stress::Retrato.marcas(@mundo.account)
    @bomba.drenar
    Stress::Retrato.new(self).turno(mensagens: mensagens, desde: antes, latencia: @bomba.latencia!)
  end
end
