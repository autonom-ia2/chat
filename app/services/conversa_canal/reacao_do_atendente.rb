# Reação do ATENDENTE a uma mensagem do WhatsApp (#1702), como no app: emoji no balão, emoji vazio tira a reação.
#
# Ordem: confere a mensagem e a caixa, manda ao provedor e só então grava em `content_attributes.reactions` (pelo
# Whatsapp::ReactionRecorder, com sender_type 'User'). Recusa do provedor: nada é gravado e a frase vai para a tela.
#
# - WhatsApp oficial (Cloud API) e caixa híbrida: pela Cloud API, o mesmo caminho do texto dentro da janela. A Meta
#   lista a reação entre as mensagens de atendimento, que só saem com a janela de 24 h aberta; fora dela, recusa. A
#   reação é a uma mensagem recebida do cliente ("a previous WhatsApp user message that you have received").
#   https://developers.facebook.com/docs/whatsapp/cloud-api/messages/reaction-messages
#   https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-messages
# - Caixa WhatsApp API (WAHA): PUT /api/reaction; sem janela de 24 h, e vale para recebida ou enviada, como no app.
class ConversaCanal::ReacaoDoAtendente
  class Recusa < StandardError; end

  def initialize(message:, user:, emoji:)
    @message = message
    @user = user
    @emoji = emoji.to_s.strip
  end

  # -> a mensagem reagida, com as reações gravadas. Levanta Recusa com a frase para a tela.
  def perform
    validar!
    remetente.enviar(@emoji)
    gravar
  end

  private

  def conversa
    @message.conversation
  end

  def canal
    @message.inbox.channel
  end

  def validar!
    recusar!(:emoji_invalido) unless um_emoji_ou_vazio?
    recusar!(:mensagem_invalida) unless reagivel?
    recusar!(:caixa_sem_reacao) if remetente.nil?
    recusar!(:sem_identificacao) if @message.source_id.blank?
    remetente.validar!
  end

  # Um emoji só (um grafema: 👍🏽 e ❤️ têm mais de um código, mas são um desenho) ou vazio para tirar a reação.
  def um_emoji_ou_vazio?
    @emoji.empty? || @emoji.grapheme_clusters.size == 1
  end

  def reagivel?
    return false if @message.private? || @message.activity? || @message.template?

    atributos = @message.content_attributes.to_h
    return false if atributos['deleted'] || atributos['deleted_by_contact_at']

    @message.incoming? || @message.outgoing?
  end

  def remetente
    return @remetente if defined?(@remetente)

    @remetente = if cloud?
                   ConversaCanal::ReacaoNaCloud.new(message: @message)
                 elsif waha?
                   ConversaCanal::ReacaoNoWaha.new(message: @message)
                 end
  end

  def cloud?
    canal.is_a?(Channel::Whatsapp) && canal.provider == 'whatsapp_cloud'
  end

  def waha?
    canal.is_a?(Channel::Api) && canal.waha_provider?
  end

  def gravar
    Whatsapp::ReactionRecorder.new(
      inbox: @message.inbox, reacted_source_id: @message.source_id, emoji: @emoji, author: @user
    ).perform || @message
  end

  def recusar!(codigo)
    raise Recusa, I18n.t("conversa_canal.reacoes.#{codigo}")
  end
end
