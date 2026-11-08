# O alvo de uma execução e as pontes dele (#2499, F6): a conversa, o card ou o contato em que a automação roda, e os
# outros dois quando há caminho até eles. O Valores, os passos e o Spam leem por aqui, nunca supondo a conversa.
#
# | alvo     | conversa                             | card | contato           |
# | conversa | ela                                  | —    | conversa.contact  |
# | card     | card.primary_conversation (pode faltar) | ele | card.contact, senão o da conversa |
# | contato  | — (a da conversa nova, #2680)        | —    | ele               |
# | conta    | —                                    | —    | —                 |
#
# A conta (#2635, G7) é o alvo do conta.recorrente: a execução da ocorrência, sem conversa, card nem contato. Nenhum
# caminho do Valores começa nela; o salvar só deixa nesse gatilho os passos que não pedem alvo.
#
# Contrato com a F2 (#2498, histórico e ensaio): `rotulo`, `link` e `visivel_para?(usuario)`. O rótulo sai do i18n e do
# registro na hora, nunca é gravado.
class Autonomia::Automacao::Contexto
  TIPOS = %w[Conversation Crm::Card Contact Account].freeze
  BASES = { ::Conversation => 'conversa', ::Crm::Card => 'card', ::Contact => 'contato', ::Account => 'conta' }.freeze

  attr_reader :alvo

  # `execucao`: a execução em que o passo roda, quando há uma. A reunião do gatilho (G12) e o texto da IA (#2679) leem dela.
  # `textos`: no ensaio, que não tem execução, o texto que cada passo de IA produziria (só para mostrar).
  def self.de(alvo, execucao: nil, textos: nil) = new(alvo, execucao: execucao, textos: textos)

  # Os `textos` do ensaio (#2679): ele não chama a IA, e no lugar do texto de cada passo que escreve vai a marca de onde
  # ele entraria.
  def self.marcas_da_ia(receita, conta)
    ::Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: nil).passos
                                   .select { |passo| ::Autonomia::Automacao::Valores::PASSOS_QUE_ESCREVEM.include?(passo['tipo']) }
                                   .to_h { |passo| [passo['id'], I18n.t('autonomia.automacao.ensaio.texto_da_ia', passo: passo['id'])] }
  end

  def initialize(alvo, execucao: nil, textos: nil)
    @alvo = alvo
    @execucao = execucao
    @textos = textos
  end

  def conversa
    return @alvo if @alvo.is_a?(::Conversation)

    (@alvo.primary_conversation if @alvo.is_a?(::Crm::Card)) || conversa_nova
  end

  # Quem não tem conversa (o card sem conversa principal, o contato) usa a que a receita abriu na caixa da conversa nova
  # (ConversaNova, #2680): a do contato nessa caixa. Sem execução (o ensaio, a partida) não há caixa escolhida. Guarda
  # só a achada: antes de o passo "mensagem" abrir, a próxima pergunta procura de novo.
  def conversa_nova
    return unless @execucao

    conversa_nova = ::Autonomia::Automacao::ConversaNova
    @conversa_nova ||= conversa_nova.existente(conversa_nova.da_execucao(@execucao), contato)
  end

  def card = (@alvo if @alvo.is_a?(::Crm::Card))

  # A conta do alvo; no conta.recorrente, a própria.
  def conta = (@alvo.is_a?(::Account) ? @alvo : @alvo.account)

  def conta_id = (@alvo.is_a?(::Account) ? @alvo.id : @alvo.account_id)

  def contato
    return @alvo if @alvo.is_a?(::Contact)
    return @alvo.contact if @alvo.is_a?(::Conversation)

    @alvo.contact || @alvo.primary_conversation&.contact if @alvo.is_a?(::Crm::Card)
  end

  # A reunião do gatilho de reunião (G12): a da atividade que disparou, achada pela marca da execução e sempre presa ao
  # card e à conta do alvo (parecer do Funções), nunca só pelo id. Num passo que roda dias depois ela é relida: a
  # reunião remarcada de novo traz o horário novo. Fora do gatilho de reunião, ou sem a atividade, nil.
  def reuniao
    return @reuniao if defined?(@reuniao)

    @reuniao = (reuniao_da_atividade if card && @execucao && ::Autonomia::Automacao::Gatilhos.de_reuniao?(@execucao.chave_gatilho))
  end

  # A última mensagem que esta execução mandou ao cliente (#2680, `envio.*`), pelo `mensagem_id` dos registros dos
  # passos: o "mensagem", o "escrever" e o "email". A nota do "avisar" também leva o id, mas não é envio ao cliente.
  def ultimo_envio
    return unless @execucao

    ids = @execucao.registros.where(resultado: 'ok').where("dados ? 'mensagem_id'").pluck(Arel.sql("dados->>'mensagem_id'"))
    # reorder: a Message ordena por created_at no default_scope, e o order só desempataria.
    ::Message.where(account_id: @execucao.account_id, id: ids, private: false, message_type: :outgoing).reorder(id: :desc).first
  end

  # #2679: o texto que o passo de IA `passo_id` produziu nesta execução (Execucao#guardar_texto!). Antes do passo rodar,
  # nil.
  def texto_da_ia(passo_id) = (@textos || @execucao&.textos).to_h[passo_id.to_s]

  # "conversa", "card" ou "contato": a base dos caminhos do Valores que o alvo tem sem ponte.
  def base
    BASES.find { |classe, _| @alvo.is_a?(classe) }&.last
  end

  # O Spam (F3.5) vale para a conversa, para a conversa principal do card e para o contato cuja única conversa está lá.
  def no_spam?
    return ::ConversaCanal::PastaDoEmail.no_spam?(conversa) if conversa
    return false unless @alvo.is_a?(::Contact)

    conversas = ::Conversation.where(account_id: @alvo.account_id, contact_id: @alvo.id).limit(2).to_a
    conversas.one? && ::ConversaCanal::PastaDoEmail.no_spam?(conversas.first)
  end

  def rotulo
    case @alvo
    when ::Conversation then I18n.t('autonomia.automacao.alvo.conversa', id: @alvo.display_id)
    when ::Crm::Card then I18n.t('autonomia.automacao.alvo.card', id: @alvo.id, titulo: @alvo.title)
    when ::Contact then I18n.t('autonomia.automacao.alvo.contato', nome: @alvo.name.presence || @alvo.id)
    when ::Account then I18n.t('autonomia.automacao.alvo.conta')
    end
  end

  def link
    conta = conta_id
    case @alvo
    when ::Conversation then "accounts/#{conta}/conversations/#{@alvo.display_id}"
    when ::Crm::Card then "accounts/#{conta}/crm?pipeline_id=#{@alvo.pipeline_id}&card_id=#{@alvo.id}"
    when ::Contact then "accounts/#{conta}/contacts/#{@alvo.id}"
    when ::Account then "accounts/#{conta}/automacoes"
    end
  end

  # A mesma pergunta que a leitura faria: a política da conversa (view?, que no EE também deixa quem só lê,
  # conversation_view), a do card ou a do contato. Para agir no alvo, a pergunta é a do Acesso#alcanca?.
  def visivel_para?(usuario)
    account_user = usuario && conta.account_users.find_by(user_id: usuario.id)
    return false unless account_user
    # A execução da conta mostra o que a automação fez (a campanha, os passos): só quem vê as automações.
    return account_user.permission_granted?('automation_view') if @alvo.is_a?(::Account)

    contexto = { user: usuario, account: conta, account_user: account_user }
    case @alvo
    when ::Conversation then ConversationPolicy.new(contexto, @alvo).view?
    when ::Crm::Card then ::Crm::CardPolicy.new(contexto, @alvo).show?
    when ::Contact then ContactPolicy.new(contexto, @alvo).show?
    else false
    end
  end

  private

  def reuniao_da_atividade
    atividade_id = ::Autonomia::Automacao::Gatilhos.atividade_da_marca(@execucao.evento)
    atividade = atividade_id && ::Crm::Activity.find_by(id: atividade_id, account_id: card.account_id, card_id: card.id)
    reuniao_id = atividade&.payload.to_h['meeting_id']
    reuniao_id && card.account.crm_meetings.find_by(id: reuniao_id, card_id: card.id)
  end
end
