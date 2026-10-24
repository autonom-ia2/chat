# Reação do ATENDENTE a uma mensagem do WhatsApp (#1702) e do Instagram (#2113), como no app: emoji no balão, emoji vazio tira a reação.
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
# - Caixa WAHA comum com a flag `whatsapp_rich_native` e motor que declara a reação (#1709): quem grava
#   (Waha::RichNative::Reactions, a reação é da empresa) e leva ao cliente (evento c2y_message_reaction ao conector) é o
#   Waha::RichNative::MessageActions.react!; aqui não se chama o PUT /api/reaction nem o `gravar`.
# - Caixa Instagram (login do Instagram, #2113): sender_action react/unreact na API do Instagram
#   (ConversaCanal::ReacaoNoInstagram); como na Cloud, só mensagem do cliente e com a janela aberta. A caixa do Instagram
#   ligada por página do Facebook não reage pelo painel (recebe e mostra a reação do cliente, Instagram::ReacaoDoCliente).
class ConversaCanal::ReacaoDoAtendente
  class Recusa < StandardError; end

  # Recusa do Waha::RichNative::MessageActions.react! (#1709) -> frase da tela; outro motivo cai em mensagem_invalida.
  MOTIVOS_DO_CONECTOR = { forbidden: :caixa_sem_reacao, invalid: :mensagem_invalida }.freeze

  def initialize(message:, user:, emoji:)
    @message = message
    @user = user
    # Só texto: lista ou objeto no lugar do emoji é recusado, nunca vira "tirar a reação".
    @emoji = emoji.is_a?(String) ? emoji.strip : nil
  end

  # -> a mensagem reagida, com as reações gravadas. Levanta Recusa com a frase para a tela.
  def perform
    return reagir_pelo_conector if pelo_conector?

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
    # O Instagram diz a própria frase (ReacaoNoInstagram#validar!).
    recusar!(:sem_identificacao) if @message.source_id.blank? && !instagram?
    remetente.validar!
  end

  # Um emoji só ou vazio para tirar a reação: a regra única do Whatsapp::EmojiDeReacao.
  def um_emoji_ou_vazio?
    Whatsapp::EmojiDeReacao.valido?(@emoji)
  end

  # A regra única do Whatsapp::MensagemReagivel (a mesma do painel na caixa WAHA).
  def reagivel?
    Whatsapp::MensagemReagivel.reagivel?(@message)
  end

  def remetente
    return @remetente if defined?(@remetente)

    @remetente = if cloud?
                   ConversaCanal::ReacaoNaCloud.new(message: @message)
                 elsif waha?
                   ConversaCanal::ReacaoNoWaha.new(message: @message)
                 elsif instagram?
                   ConversaCanal::ReacaoNoInstagram.new(message: @message)
                 end
  end

  def cloud?
    canal.is_a?(Channel::Whatsapp) && canal.provider == 'whatsapp_cloud'
  end

  def waha?
    canal.is_a?(Channel::Api) && canal.waha_provider?
  end

  def instagram?
    canal.is_a?(Channel::Instagram)
  end

  def pelo_conector?
    waha? && Waha::RichNative::MessageActions.allowed?(conversa, 'react')
  end

  # As validações do caminho de sempre que valem aqui: emoji e mensagem reagível (nem nota, atividade, modelo nem
  # apagada). `sem_identificacao` não: o conector acha a mensagem pelo id do chat2you, sem `source_id`.
  def reagir_pelo_conector
    recusar!(:emoji_invalido) unless um_emoji_ou_vazio?
    recusar!(:mensagem_invalida) unless reagivel?
    motivo = Waha::RichNative::MessageActions.react!(@message, user: @user, emoji: @emoji)
    recusar!(MOTIVOS_DO_CONECTOR.fetch(motivo, :mensagem_invalida)) if motivo

    @message.reload
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
