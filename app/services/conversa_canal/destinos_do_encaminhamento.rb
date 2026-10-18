# "Conversas recentes" da janela "Encaminhar mensagem para" (#1702): as conversas que o usuário vê (a mesma regra da
# lista de conversas, Conversations::PermissionFilterService, que o EE estende com as funções personalizadas), da mais
# recente para a mais antiga. Com termo, filtra pelo nome, telefone ou e-mail do contato. Cada linha traz a última
# mensagem da conversa (sem nota nem atividade), como a linha de baixo da lista do WhatsApp.
class ConversaCanal::DestinosDoEncaminhamento
  LIMITE = 20
  TAMANHO_DA_LINHA = 80

  def initialize(user:, account:, termo: nil)
    @user = user
    @account = account
    @termo = termo.to_s.strip
  end

  def perform
    conversas = visiveis.includes(:contact, :inbox).reorder(last_activity_at: :desc).limit(LIMITE).to_a
    linhas = ultimas_linhas(conversas.map(&:id))
    conversas.map { |conversa| linha(conversa, linhas[conversa.id]) }
  end

  private

  def visiveis
    Conversations::PermissionFilterService.new(filtradas, @user, @account).perform
  end

  def filtradas
    return @account.conversations if @termo.blank?

    parecido = "%#{ActiveRecord::Base.sanitize_sql_like(@termo)}%"
    @account.conversations.joins(:contact)
            .where('contacts.name ILIKE :t OR contacts.phone_number ILIKE :t OR contacts.email ILIKE :t', t: parecido)
  end

  def ultimas_linhas(ids)
    return {} if ids.empty?

    Message.chat.where(conversation_id: ids).where.not(content: [nil, ''])
           .reorder('messages.conversation_id, messages.created_at DESC')
           .select('DISTINCT ON (messages.conversation_id) messages.conversation_id, messages.content')
           .to_h { |mensagem| [mensagem.conversation_id, mensagem.content.to_s.lines.first.to_s.strip.first(TAMANHO_DA_LINHA)] }
  end

  def linha(conversa, ultima)
    contato = conversa.contact
    {
      id: conversa.display_id,
      nome: contato&.name.presence || contato&.phone_number.to_s,
      telefone: contato&.phone_number,
      avatar: contato&.avatar_url,
      ultima_linha: ultima,
      caixa: conversa.inbox&.name
    }
  end
end
