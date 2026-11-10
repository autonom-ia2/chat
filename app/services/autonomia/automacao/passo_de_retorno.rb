# O passo "criar retorno" (G3, #2629): um lembrete para a equipe, com ou sem a mensagem ao cliente na hora (o envio
# automático do Followup). Vira o mesmo pedido da tela, `POST crm/follow_ups`, pela mesma porta da ação (PassoDeAcao),
# como quem ligou: o Pundit do retorno (crm_manage_cards no EE), o card e a conversa que essa pessoa enxerga e toda a
# validação do Crm::FollowUps::Creator (o envio automático só no card, o modelo só de utilidade, o opt-out) valem como
# na tela. O que a plataforma recusa vira motivo no histórico.
#
# - título e mensagem: pedaços e valores do alvo, como o texto da mensagem; valor vazio pula o passo;
# - quando: daqui a N minutos, horas ou dias; ou (G57) hoje ou amanhã, numa hora ou no fim do dia, no fuso da conta. A
#   hora de hoje que já passou vale em seguida, nunca amanhã;
# - para: o responsável (no card, quem cuida do cliente; na conversa, o responsável dela), pessoas ou um time; sem
#   responsável, o passo pula;
# - no card, o retorno é dele (e da conversa principal); na conversa e no contato, é do contato, só como lembrete. Por
#   isso a mensagem ao cliente só vale com gatilho de card, conferido ao salvar.
class Autonomia::Automacao::PassoDeRetorno
  ACAO = 'POST crm/follow_ups'.freeze
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  # Ao salvar: os valores do título e da mensagem lidos pelo bloco de quem confere a receita (Receita#problemas_do_caminho),
  # a mensagem só com a flag da F4 e só no card (`alvo`, Receita#alvo: o gatilho de card ou o ramo nos cards do contato),
  # as pessoas e o time da própria conta e, com a pessoa, poder criar retorno (FollowUpPolicy#create?, como o "criar
  # card" do G4). `account_user` nil (o catálogo) não confere a pessoa.
  def self.problemas_ao_salvar(conta, passo, alvo, account_user, &)
    textos = [passo['titulo'], passo.dig('envio', 'mensagem')].compact
    lidos = textos.flat_map { |partes| ::Autonomia::Automacao::Texto.caminhos(partes) }.flat_map(&)
    da_mensagem(conta, passo, alvo) + de_quem_salva(passo, account_user) + lidos + de_fora(conta, passo)
  end

  def self.da_mensagem(conta, passo, alvo)
    return [] unless passo['envio']
    return [frase(:passo_desligado, passo: passo['id'])] unless ::Autonomia::Automacao::Motor.mensagens?(conta)
    return [] if alvo == ::Autonomia::Automacao::Gatilhos::CARD

    [frase(:retorno_mensagem_sem_card, passo: passo['id'])]
  end

  def self.de_quem_salva(passo, account_user)
    account_user.nil? || cria_retorno?(account_user) ? [] : [frase(:sem_criar_retorno, passo: passo['id'])]
  end

  def self.cria_retorno?(account_user)
    contexto = { user: account_user.user, account: account_user.account, account_user: account_user }
    ::Crm::FollowUpPolicy.new(contexto, ::Crm::FollowUp).create?
  end

  def self.de_fora(conta, passo)
    para = passo['para'].to_h
    pessoas = Array(para['pessoas']) - conta.users.where(id: para['pessoas']).pluck(:id)
    times = Array(para['time']) - conta.teams.where(id: para['time']).pluck(:id)
    pessoas.map { |pessoa| frase(:pessoa_de_fora, passo: passo['id'], id: pessoa) } +
      times.map { |time| frase(:time_de_fora, passo: passo['id'], id: time) }
  end

  # O ensaio (Ensaio#retorno): [o que faria, dados], na ordem do #executar: o título montado, ou por que pularia. Só
  # descreve; nada é criado.
  def self.ensaiar(passo, valores, conta)
    return ['mensagens_desligadas'] if passo['envio'] && !::Autonomia::Automacao::Motor.mensagens?(conta)

    motivo = pulo_dos_textos(passo, valores)
    return [motivo] if motivo
    return ['retorno_sem_responsavel'] if [nil, 'responsavel'].include?(passo.dig('para', 'quem')) &&
                                          valores.ler('conversa.responsavel_id').blank?

    ['retorno', { texto: ::Autonomia::Automacao::Texto.new(passo['titulo'], valores).montar }]
  end

  # O primeiro pulo do título e da mensagem do retorno, na ordem do motor: valor vazio ou texto só de espaços.
  def self.pulo_dos_textos(passo, valores)
    textos = passo['envio'] ? [passo['titulo'], passo.dig('envio', 'mensagem')] : [passo['titulo']]
    textos.lazy.map { |partes| pulo_do_texto(::Autonomia::Automacao::Texto.new(partes, valores).montar) }.find(&:itself)
  end

  def self.pulo_do_texto(pronto)
    return 'faltou_valor' if pronto.nil?

    'texto_vazio' if pronto.strip.empty?
  end

  def self.frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  def initialize(execucao:, passo:, valores:, acesso:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
    @contexto = ::Autonomia::Automacao::Contexto.de(execucao.alvo)
  end

  def executar
    return pulado('mensagens_desligadas') if envio? && !::Autonomia::Automacao::Motor.mensagens?(@execucao.account)

    titulo = montado(@passo['titulo'])
    mensagem = montado(@passo.dig('envio', 'mensagem')) if envio?
    return titulo if titulo.is_a?(Resultado)
    return mensagem if mensagem.is_a?(Resultado)

    para = destinatarios
    return pulado('retorno_sem_responsavel') if para.nil?

    ::Autonomia::Automacao::PassoDeAcao.new(execucao: @execucao, passo: passo_da_acao(titulo, mensagem, para), valores: @valores,
                                            acesso: @acesso, acoes: ::Autonomia::Automacao::AcoesDoRetorno).executar
  end

  private

  def envio? = @passo['envio'].present?

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: {})

  # O texto pronto, ou o pulo: valor vazio (faltou_valor) ou texto só de espaços (texto_vazio).
  def montado(partes)
    pronto = ::Autonomia::Automacao::Texto.new(partes, @valores).montar
    return pulado('faltou_valor') if pronto.nil?

    pronto.strip.empty? ? pulado('texto_vazio') : pronto
  end

  # recipient_* do Followup, ou nil quando é o responsável e a conversa (ou o contato) não tem.
  def destinatarios
    para = @passo['para'].to_h
    case para['quem']
    when 'pessoas' then { recipient_mode: 'users', recipient_user_ids: para['pessoas'] }
    when 'time' then { recipient_mode: 'team', recipient_team_id: para['time'] }
    else responsavel
    end
  end

  def responsavel
    card = @contexto.card
    return { recipient_mode: 'card_owner' } if card&.owner_id
    return if card

    assignee = @contexto.conversa&.assignee_id
    { recipient_mode: 'users', recipient_user_ids: [assignee] } if assignee
  end

  def passo_da_acao(titulo, mensagem, para)
    { 'id' => @passo['id'], 'tipo' => 'acao', 'acao' => ACAO, 'descricao' => titulo, 'corpo' => corpo(titulo, mensagem, para) }
  end

  def corpo(titulo, mensagem, para)
    {
      'title' => titulo, 'due_at' => quando.iso8601, 'timezone' => fuso.tzinfo.name,
      'follow_up_type' => mensagem ? 'message' : 'task',
      'automation_mode' => mensagem ? 'auto_send_message' : 'reminder_only',
      'metadata' => mensagem ? { 'message_body' => mensagem } : nil,
      **dono, **para.stringify_keys
    }.compact
  end

  # No card, o retorno é dele (a conversa principal vem pelo controller); fora dele, do contato.
  def dono
    return { 'card_id' => @contexto.card.id } if @contexto.card

    { 'contact_id' => @contexto.contato&.id }
  end

  def quando
    return Time.current + ::Autonomia::Automacao::Duracao.de(@passo['daqui']) if @passo['daqui']

    no_dia(@passo['quando'])
  end

  # G57: o dia no fuso da conta; sem hora, o fim dele; hora que já passou, agora.
  def no_dia(quando)
    agora = Time.current.in_time_zone(fuso)
    dia = quando['dia'] == 'amanha' ? agora.to_date.tomorrow : agora.to_date
    hora = quando['hora']
    return fuso.local(dia.year, dia.month, dia.day).end_of_day if hora.nil?

    [fuso.local(dia.year, dia.month, dia.day, hora), agora].max
  end

  # O fuso que a tela grava na conta (#954), o mesmo do extrair e do Guia.
  def fuso
    conta = @execucao.account
    ::Crm::Timezone::Resolver.new(explicit: conta.custom_attributes.to_h['timezone'], account: conta).zone_or_default
  end
end
