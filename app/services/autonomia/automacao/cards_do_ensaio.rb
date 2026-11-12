# Os cards em que o Ensaio roda um gatilho de card (#2631): cards reais da conta, nunca inventados. Só lê.
#
# - Só os que quem ensaia alcança, pelas perguntas do motor (Acesso#alcanca?) feitas a essa pessoa: o card pela política
#   do CRM (Crm::CardPolicy::Scope) e a conversa principal dele, quando há, pela política da conversa. A chave de funis
#   o controller confere antes, como no salvar.
# - No funil e na etapa que o gatilho escolheu. Os parâmetros de tempo (dias, data do campo, antes da reunião) não
#   escolhem: o ensaio mostra o que faria se a hora chegasse agora, como o de conversa mostra o que faria se o evento
#   acontecesse agora. No "saiu da etapa", os cards que estão nela: os que sairiam.
# - Nos gatilhos de reunião (G12), a reunião que o gatilho leria em cada card (`reuniao.*`): a agendada (marcada,
#   remarcada, lembrete), a cancelada ou a atendida, a mais recente, na página escolhida (G32). Os cards com ela vêm
#   primeiro; o card sem ela não entraria (`sem_reuniao`).
#
# A mesma interface do ConversasDoEnsaio: o Ensaio não pergunta qual é.
class Autonomia::Automacao::CardsDoEnsaio
  AGENDADA = { status: :scheduled }.freeze
  REUNIAO = { 'card.reuniao_cancelada' => { status: :canceled }, 'card.reuniao_atendida' => { outcome: :held } }.freeze

  def initialize(gatilho:, conta:, usuario:)
    @gatilho = gatilho
    @conta = conta
    @usuario = usuario
    @account_user = conta.account_users.find_by(user_id: usuario.id)
  end

  # Os `limite` mais recentes; nos gatilhos de reunião, os que têm a reunião primeiro.
  def recentes(limite)
    primeiros = reuniao? ? alcancados(cards.where(id: reunioes.select(:card_id)), limite) : []
    primeiros + alcancados(cards.where.not(id: primeiros.map(&:id)), limite - primeiros.size)
  end

  # O card escolhido em "Ensaiar em outro card"; fora do alcance de quem pede, é como se não existisse (RecordNotFound).
  def um(id)
    card = cards.find(id)
    raise ActiveRecord::RecordNotFound unless alcanca?(card)

    card
  end

  # O que a tela mostra: o id e o título do card no lugar do número da conversa e do nome do contato.
  def base(card) = { conversa_id: card.id, nome: card.title, ultima_atividade: card.updated_at }

  # Card não tem mensagem do gatilho; o fato é a reunião que o gatilho de reunião leria (nil nos outros, ou sem ela).
  def gatilho_de(card)
    [nil, (reunioes.where(card_id: card.id).reorder(starts_at: :desc, id: :desc).first if reuniao?)]
  end

  # G12: no gatilho de reunião, o card sem a reunião que o gatilho leria não entraria.
  def motivo(_card, _mensagem, reuniao) = ('sem_reuniao' if reuniao? && reuniao.nil?)

  private

  def reuniao? = ::Autonomia::Automacao::Gatilhos.de_reuniao?(@gatilho['tipo'])

  def reunioes
    escopo = @conta.crm_meetings.where(REUNIAO.fetch(@gatilho['tipo'], AGENDADA))
    pagina = @gatilho['pagina_id']
    pagina.nil? ? escopo : escopo.where('crm_meetings.metadata ->> ? = ?', ::Autonomia::Automacao::ReuniaoDaAtividade::PAGINA, pagina.to_s)
  end

  def cards
    escopo = Pundit.policy_scope!(contexto, ::Crm::Card).where(account_id: @conta.id)
    escopo = escopo.where(pipeline_id: @gatilho['funil_id']) if @gatilho['funil_id']
    @gatilho['etapa_id'] ? escopo.where(stage_id: @gatilho['etapa_id']) : escopo
  end

  def alcancados(escopo, limite)
    escopo.includes(:primary_conversation).reorder(updated_at: :desc, id: :desc).limit(limite).to_a.select { |card| alcanca?(card) }
  end

  # O card já veio do escopo de quem pede; falta a conversa em que os passos agiriam (Contexto#conversa), a mesma
  # pergunta da leitura (Contexto#visivel_para?).
  def alcanca?(card)
    conversa = card.primary_conversation
    conversa.nil? || ConversationPolicy.new(contexto, conversa).view?
  end

  def contexto = { user: @usuario, account: @conta, account_user: @account_user }
end
