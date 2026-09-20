# O Guia que enxerga (issue #533): leitura SÓ-LEITURA do que a conta tem, para
# responder "quais", "quantos" e "qual" com os dados, não com o manual.
#
# Autorização é herdada, não reescrita: cada assunto passa pelo mesmo
# `policy_scope` do Pundit que os controllers usam, com o mesmo user_context.
# Assim o agente comum enxerga pelo Guia exatamente o que enxergaria clicando,
# e nunca dado de outra conta.
#
# Devolve frases em pt_BR (não JSON): elas entram no contexto do modelo como
# DADO, no mesmo bloco [ESTADO REAL DA CONTA] que o diagnóstico já usa.
class Autonomia::Guide::Leituras
  ASSUNTOS = %w[caixas funis campanhas times horario].freeze

  # Assuntos que expõem configuração da conta: só administrador.
  SO_ADMIN = %w[funis campanhas horario].freeze

  LIMITE = 15

  def self.run(assunto, account:, user:, account_user: nil)
    new(account: account, user: user, account_user: account_user).run(assunto)
  end

  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || account&.account_users&.find_by(user_id: user&.id)
  end

  # Tri-state, igual ao Diagnostics: Array<String> com o que foi lido (pode vir
  # vazio), ou nil quando a leitura falhou — para o Guia nunca transformar erro
  # em "não há nada".
  def run(assunto)
    return nil unless ASSUNTOS.include?(assunto.to_s)
    return ['Esta informação é da configuração da conta, e quem vê é o administrador.'] if bloqueado?(assunto)

    com_contexto { send(assunto.to_s) }
  rescue StandardError => e
    Rails.logger.error("[autonomia][guide][leituras] #{assunto} account=#{@account&.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def bloqueado?(assunto)
    SO_ADMIN.include?(assunto.to_s) && !administrador?
  end

  def administrador?
    @account_user&.role.to_s == 'administrator'
  end

  # Nome de caixa, de funil e de campanha é texto que o cliente escreve e que vai
  # parar no contexto do modelo. Mesma higiene do Diagnostics: sem colchetes, sem
  # quebra de linha, sem controle, com tamanho limitado.
  def safe(str)
    str.to_s.gsub(/[\[\]\r\n]/, ' ').gsub(/[[:cntrl:]]/, ' ').squeeze(' ').strip[0, 80].to_s
  end

  def contexto
    { user: @user, account: @account, account_user: @account_user }
  end

  # As políticas do app leem o contexto da requisição (`Current`) para resolver o
  # que este usuário enxerga. Aqui ele é declarado explicitamente, a partir de
  # quem pediu, e devolvido ao estado anterior: a leitura não pode depender de
  # quem chamou, nem deixar a conta trocada para o resto da requisição.
  def com_contexto
    conta_anterior = Current.account
    usuario_anterior = Current.user
    vinculo_anterior = Current.account_user

    Current.account = @account
    Current.user = @user
    Current.account_user = @account_user
    yield
  ensure
    Current.account = conta_anterior
    Current.user = usuario_anterior
    Current.account_user = vinculo_anterior
  end

  def escopo(classe)
    Pundit.policy_scope!(contexto, classe)
  end

  def caixas
    lista = escopo(Inbox).includes(:channel).limit(LIMITE).to_a
    return ['A conta ainda não tem caixa de entrada.'] if lista.empty?

    lista.map do |inbox|
      "Caixa \"#{safe(inbox.name)}\": canal #{canal_legivel(inbox)}."
    end
  end

  def canal_legivel(inbox)
    return 'WhatsApp' if inbox.whatsapp?
    return 'E-mail' if inbox.email?
    return 'API' if inbox.api?

    inbox.channel_type.to_s.split('::').last.presence || 'desconhecido'
  end

  def funis
    lista = @account.crm_pipelines.limit(LIMITE).to_a
    return ['A conta ainda não tem funil criado.'] if lista.empty?

    lista.map { |pipeline| descrever_funil(pipeline) }
  end

  def descrever_funil(pipeline)
    vinculos = @account.crm_pipeline_inboxes.includes(:inbox).where(pipeline_id: pipeline.id).to_a
    return "Funil \"#{safe(pipeline.name)}\": nenhuma caixa alimenta este funil." if vinculos.empty?

    caixas = vinculos.map do |vinculo|
      estado = vinculo.auto_create_card? ? 'cria card sozinho' : 'sem criação automática'
      "#{safe(vinculo.inbox&.name)} (#{estado})"
    end
    "Funil \"#{safe(pipeline.name)}\": recebe de #{caixas.join(', ')}."
  end

  def campanhas
    lista = escopo(Campaign).limit(LIMITE).to_a
    return ['A conta ainda não tem campanha criada.'] if lista.empty?

    ativas = lista.count(&:enabled?)
    ["A conta tem #{lista.size} campanha(s), sendo #{ativas} ativa(s).",
     *lista.first(5).map { |c| "Campanha \"#{safe(c.title)}\": #{c.enabled? ? 'ativa' : 'parada'}." }]
  end

  def times
    lista = escopo(Team).limit(LIMITE).to_a
    return ['A conta ainda não tem time criado.'] if lista.empty?

    lista.map { |time| "Time \"#{safe(time.name)}\": #{time.team_members.count} pessoa(s)." }
  end

  def horario
    lista = escopo(Inbox).limit(LIMITE).to_a
    return ['A conta ainda não tem caixa de entrada.'] if lista.empty?

    lista.map do |inbox|
      if inbox.working_hours_enabled?
        "Caixa \"#{safe(inbox.name)}\": horário de atendimento ligado, fuso #{safe(inbox.timezone)}."
      else
        "Caixa \"#{safe(inbox.name)}\": atende a qualquer hora (horário de atendimento desligado)."
      end
    end
  end
end
