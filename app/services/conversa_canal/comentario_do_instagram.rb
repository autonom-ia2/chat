# Comentários na caixa (#2215): o comentário do Instagram de onde a conversa nasceu (IA cuida dos comentários, #2212:
# `additional_attributes.meta_ads_comment`), lido ao vivo na Meta, e as ações nele sem sair da conversa: responder em
# público, esconder ou mostrar de novo, e apagar. As chamadas e o registro em crm_meta_ads_comment_actions são os de
# Seus posts (SeusPosts::ComentariosInstagram, #2305), que confere na Meta que o comentário é do post gravado na
# conversa. O texto do comentário é de terceiro: não é gravado (nem na atividade de apagar).
#
# Cada ação vira uma linha de atividade na conversa, no idioma da conta, com quem fez. Erros: os de
# SeusPosts::ComentariosInstagram (`comment_not_found`, `invalid_text`, `needs_permission`, `meta_unavailable`,
# `meta_refused`).
class ConversaCanal::ComentarioDoInstagram
  Error = Crm::MetaAds::InstagramPrivateReply::Error
  NETWORK = 'instagram'.freeze
  ATIVIDADE = 'conversations.activity.meta_ads_comment'.freeze

  # A conversa nasceu de um comentário do Instagram, numa caixa do Instagram, com comentário e post gravados. A prova é
  # do servidor: `additional_attributes` aceita qualquer coisa de quem cria a conversa pela API, então só vale o
  # comentário que tem, em crm_meta_ads_comment_actions, uma linha ligada a ESTA conversa (o motor grava a do privado
  # em `vincular!` e a da passagem em `gravar!(conversation:)`). Só a linha da IA: o privado que uma pessoa manda pela
  # tela pode cair numa conversa aberta que alguém criou pela API com o atributo forjado, e não vale como prova.
  # Sem ela, a conversa não age em comentário nenhum.
  def self.da_conversa(conversation)
    origem = conversation.additional_attributes.to_h['meta_ads_comment']
    return unless origem.is_a?(Hash) && origem['network'] == NETWORK && conversation.inbox.channel.is_a?(Channel::Instagram)
    return if origem['comment_id'].blank? || origem['post_id'].blank?
    return unless nasceu_do_comentario?(conversation, origem['comment_id'].to_s)

    new(conversation, origem)
  end

  def self.nasceu_do_comentario?(conversation, comment_id)
    Crm::MetaAdsCommentAction.exists?(account_id: conversation.account_id, network: NETWORK, comment_id: comment_id,
                                      conversation_id: conversation.id, actor: Crm::MetaAds::ComentariosIa::Registro::ACTOR)
  end

  def initialize(conversation, origem)
    @conversation = conversation
    @canal = conversation.inbox.channel
    @comment_id = origem['comment_id'].to_s
    @post_id = origem['post_id'].to_s
    @anuncio = origem['ad_id'].present?
  end

  attr_reader :comment_id, :post_id

  # { status: 'ok', comentario: {...} } ou status `apagado`, `needs_permission`, `meta_unavailable`. Apagado pela
  # conta (linha `delete`) não chama a Meta.
  def ler
    return { status: 'apagado' } if apagado_pela_conta?

    result = cliente.comment(@comment_id)
    return { status: falha(result) } unless result.ok
    return { status: 'apagado' } if de_outro_post?(result.data)

    { status: 'ok', comentario: comentario(result.data) }
  end

  def responder!(texto, user:)
    acoes.reply!(@post_id, @comment_id, texto, user: user)
    atividade!('public_reply', user, text: texto.to_s.strip.truncate(500))
    { resposta: { texto: texto.to_s.strip } }
  end

  def esconder!(hidden, user:)
    acoes.hide!(@post_id, @comment_id, hidden: hidden, user: user)
    atividade!(hidden ? 'hidden' : 'shown', user)
    { escondido: hidden }
  end

  # Irreversível: some do Instagram. A tela confirma antes.
  def apagar!(user:)
    acoes.delete!(@post_id, @comment_id, user: user)
    atividade!('deleted', user)
    { status: 'apagado' }
  end

  private

  def comentario(data)
    username = data.dig('from', 'username')
    { id: data['id'].to_s, autor: username.present? ? "@#{username}" : nil, texto: data['text'], quando: data['timestamp'],
      escondido: data['hidden'] == true, onde: @anuncio ? 'anuncio' : 'post' }
  end

  # O comentário que a Meta não acha mais foi apagado (no Instagram ou por outra tela).
  def falha(result)
    return 'needs_permission' if result.scope_error? || result.token_invalid?
    return 'apagado' if result.object_error?

    'meta_unavailable'
  end

  def de_outro_post?(data)
    data.dig('media', 'id').to_s != @post_id
  end

  def apagado_pela_conta?
    Crm::MetaAdsCommentAction.exists?(account_id: @conversation.account_id, network: NETWORK, comment_id: @comment_id, action: 'delete')
  end

  # A Meta já agiu quando isto roda: falha ao gravar a atividade vai ao rastreador e a resposta diz a verdade.
  def atividade!(chave, user, **)
    conteudo = I18n.with_locale(@conversation.account.locale) { I18n.t("#{ATIVIDADE}.#{chave}", user_name: user.name, **) }
    @conversation.messages.create!(account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :activity,
                                   content: conteudo)
  rescue StandardError => e
    Rails.logger.error("[ComentarioDaConversa] atividade não gravada: account=#{@conversation.account_id} " \
                       "conversa=#{@conversation.display_id} acao=#{chave} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
  end

  def acoes
    @acoes ||= SeusPosts::ComentariosInstagram.new(@canal, can_manage: true, conversation_access: ->(_conversation) { false })
  end

  def cliente
    @cliente ||= Instagram::CommentsClient.new(@canal)
  end
end
