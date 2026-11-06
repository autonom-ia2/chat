# O alvo de uma execução e as pontes dele (#2499, F6): a conversa, o card ou o contato em que a automação roda, e os
# outros dois quando há caminho até eles. O Valores, os passos e o Spam leem por aqui, nunca supondo a conversa.
#
# | alvo     | conversa                             | card | contato           |
# | conversa | ela                                  | —    | conversa.contact  |
# | card     | card.primary_conversation (pode faltar) | ele | card.contact, senão o da conversa |
# | contato  | —                                    | —    | ele               |
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

  def self.de(alvo) = new(alvo)

  def initialize(alvo)
    @alvo = alvo
  end

  def conversa
    return @alvo if @alvo.is_a?(::Conversation)

    @alvo.primary_conversation if @alvo.is_a?(::Crm::Card)
  end

  def card = (@alvo if @alvo.is_a?(::Crm::Card))

  # A conta do alvo; no conta.recorrente, a própria.
  def conta = (@alvo.is_a?(::Account) ? @alvo : @alvo.account)

  def conta_id = (@alvo.is_a?(::Account) ? @alvo.id : @alvo.account_id)

  def contato
    return @alvo if @alvo.is_a?(::Contact)
    return @alvo.contact if @alvo.is_a?(::Conversation)

    @alvo.contact || conversa&.contact if @alvo.is_a?(::Crm::Card)
  end

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
end
