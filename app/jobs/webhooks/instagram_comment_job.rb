# Comentário novo no Instagram (#2196): o campo `comments` do webhook do login do Instagram, que o roteador do webhook
# (Webhooks::InstagramEventsJob, infra #2200) manda para cá com o `entry.id` (a conta do Instagram), o campo, o
# `value` cru e o `entry.time`.
#
# Vira o evento comum `meta_ads.comment_received` para quem cuida dos comentários (#2212). Ficam de fora: outros
# campos (`mentions`), o eco das respostas da própria conta e Instagram sem caixa na plataforma (o relay entre stacks
# entrega o mesmo corpo às duas; cada uma só publica o que é dela). Nada do comentário é gravado aqui.
#
# O evento sai com a flag dos comentários desligada também: quem escuta (a IA, #2212) confere a flag dela. Corpo fora
# do formato (sem `from` ou `id`, tempo que não é número) é descartado em silêncio: é dado da Meta, não nosso.
class Webhooks::InstagramCommentJob < ApplicationJob
  queue_as :default

  def perform(instagram_id, field, value, time)
    return unless field == 'comments' && well_formed?(value, time)

    value = value.with_indifferent_access
    return if value[:from][:id].to_s == instagram_id.to_s

    channel = Channel::Instagram.find_by(instagram_id: instagram_id.to_s)
    return if channel&.inbox.nil?

    Rails.configuration.dispatcher.dispatch(Events::Types::META_ADS_COMMENT_RECEIVED, Time.zone.now, payload(channel, value, time))
  end

  private

  def well_formed?(value, time)
    value.is_a?(Hash) && time.is_a?(Numeric) && value.with_indifferent_access[:from].is_a?(Hash) &&
      value.with_indifferent_access[:id].present?
  end

  def payload(channel, value, time)
    media = value[:media].is_a?(Hash) ? value[:media] : {}
    {
      network: 'instagram', account_id: channel.account_id, inbox_id: channel.inbox.id, instagram_id: channel.instagram_id,
      media_id: media[:id]&.to_s, ad_id: media[:ad_id]&.to_s, comment_id: value[:id].to_s,
      parent_id: value[:parent_id]&.to_s, from_id: value.dig(:from, :id)&.to_s, from_name: value.dig(:from, :username),
      text: value[:text], created_time: Time.zone.at(time.to_i)
    }
  end
end
