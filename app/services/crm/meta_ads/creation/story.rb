# O criativo do anúncio novo (#2198, Fluxo 1): `object_story_spec` com a Página (e a conta do Instagram dela, quando há),
# a mídia, o texto, o título e o botão do destino. Uma mídia para todos os lugares.
#
# - WhatsApp: botão WHATSAPP_MESSAGE com `app_destination: WHATSAPP`; a mensagem pronta vai em `page_welcome_message`.
# - Site: o endereço e o botão escolhido (LEARN_MORE ou SHOP_NOW).
# - Messenger e Direct do Instagram: botão MESSAGE_PAGE com o `app_destination` de cada um (só entram quando a chamada
#   real confirmar; ver Crm::MetaAds::Creation::Confirmed).
# - Foto: `link_data` com `image_hash`. Vídeo: `video_data` com `video_id` e a capa em `image_hash`. Carrossel (2 a 10):
#   `link_data.child_attachments`, todos com o mesmo título e o mesmo botão.
class Crm::MetaAds::Creation::Story
  WHATSAPP_LINK = 'https://api.whatsapp.com/send'.freeze
  MESSENGER_LINK = 'https://fb.com/messenger_doc/'.freeze

  def initialize(draft, instagram_id: nil)
    @draft = draft
    @instagram_id = instagram_id
  end

  def object_story_spec
    base = { page_id: @draft[:page_id], instagram_user_id: @instagram_id }.compact
    medias = [@draft[:media], *@draft[:cards]]
    return base.merge(link_data: carousel(medias)) if medias.size > 1
    return base.merge(video_data: video(medias.first)) if medias.first[:kind] == 'video'

    base.merge(link_data: link_data.merge(image_hash: medias.first[:hash]))
  end

  private

  def link_data
    data = { message: @draft[:text], name: @draft[:headline].presence, link: link, call_to_action: call_to_action }
    data[:page_welcome_message] = welcome_message if @draft[:destination] == 'WHATSAPP' && @draft[:ready_message].present?
    data.compact
  end

  def video(media)
    { video_id: media[:video_id], image_hash: media[:image_hash], message: @draft[:text], title: @draft[:headline].presence,
      call_to_action: call_to_action }.compact
  end

  def carousel(medias)
    cards = medias.map do |media|
      card = { link: link, name: @draft[:headline].presence, call_to_action: call_to_action }
      card.merge!(media[:kind] == 'video' ? { video_id: media[:video_id], image_hash: media[:image_hash] } : { image_hash: media[:hash] })
      card.compact
    end
    link_data.merge(child_attachments: cards, multi_share_end_card: false, multi_share_optimized: false)
  end

  def link
    case @draft[:destination]
    when 'WEBSITE' then @draft[:site_url]
    when 'WHATSAPP' then WHATSAPP_LINK
    else MESSENGER_LINK
    end
  end

  def call_to_action
    case @draft[:destination]
    when 'WEBSITE' then { type: @draft[:site_action], value: { link: @draft[:site_url] } }
    when 'WHATSAPP' then { type: 'WHATSAPP_MESSAGE', value: { app_destination: 'WHATSAPP' } }
    else { type: 'MESSAGE_PAGE', value: { app_destination: @draft[:destination] } }
    end
  end

  # Mensagem que já vem escrita quando a pessoa abre o WhatsApp (confirmar o formato na chamada real).
  def welcome_message
    {
      type: 'VISUAL_EDITOR', version: 2, landing_screen_type: 'welcome_message', media_type: 'text',
      text_format: { customer_action_type: 'autofill_message',
                     message: { autofill_message: { content: @draft[:ready_message] }, text: @draft[:ready_message] } }
    }.to_json
  end
end
