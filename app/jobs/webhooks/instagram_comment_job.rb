# Comentário novo no Instagram (#2196): o campo `comments` do webhook do login do Instagram, que o roteador do webhook
# (Webhooks::InstagramEventsJob, infra #2200) manda para cá com o `entry.id` (a conta do Instagram), o campo, o
# `value` e o `entry.time`.
#
# Do `value` só valem os ids (`id`, `from.id`, `media.id`, `media.ad_id`): o texto e o username de quem comentou são
# lidos na Graph aqui, com o token da caixa, para não ficarem nos argumentos do job (fila, retry e dead set do Sidekiq
# guardam os argumentos em claro no Redis). O roteador pode mandar o `value` inteiro ou só os ids.
#
# Vira o evento comum `meta_ads.comment_received` para quem cuida dos comentários (#2212). Ficam de fora: outros
# campos (`mentions`), o eco das respostas da própria conta, Instagram sem caixa na plataforma (o relay entre stacks
# entrega o mesmo corpo às duas; cada uma só publica o que é dela) e conta sem a flag `meta_ads_comentarios_instagram`
# (sem ela a caixa não tem a permissão de ler comentários). Nada do comentário é gravado aqui. Corpo fora do formato é
# descartado em silêncio; Graph fora do ar sobe o erro para o retry (com os argumentos, que são só ids).
class Webhooks::InstagramCommentJob < ApplicationJob
  queue_as :default
  # Os ids de quem comentou ficam fora do log também (como o relay, #2200).
  self.log_arguments = false

  def perform(instagram_id, field, value, time)
    return unless field == 'comments' && well_formed?(value, time)

    value = value.with_indifferent_access
    return if own?(value.dig(:from, :id), instagram_id)

    channel = channel_for(instagram_id)
    return if channel.nil?

    comment = read_comment(channel, value[:id].to_s)
    return if comment.nil? || own?(comment.dig('from', 'id'), instagram_id)

    Rails.configuration.dispatcher.dispatch(Events::Types::META_ADS_COMMENT_RECEIVED, Time.zone.now, payload(channel, value, comment, time))
  end

  private

  def well_formed?(value, time)
    value.is_a?(Hash) && Integer(time.to_s, exception: false).present? && value.with_indifferent_access[:id].present?
  end

  def channel_for(instagram_id)
    channel = Channel::Instagram.find_by(instagram_id: instagram_id.to_s)
    channel if channel&.inbox.present? && channel.account.feature_enabled?('meta_ads_comentarios_instagram')
  end

  def own?(from_id, instagram_id)
    from_id.present? && from_id.to_s == instagram_id.to_s
  end

  def read_comment(channel, comment_id)
    result = Instagram::CommentsClient.new(channel).comment(comment_id)
    return result.data if result.ok
    raise Instagram::CommentsClient::Unavailable, comment_id if result.transient?

    nil
  end

  def payload(channel, value, comment, time)
    media = value[:media].is_a?(Hash) ? value[:media] : {}
    {
      network: 'instagram', account_id: channel.account_id, inbox_id: channel.inbox.id, instagram_id: channel.instagram_id,
      media_id: (comment.dig('media', 'id') || media[:id])&.to_s, ad_id: media[:ad_id]&.to_s, comment_id: comment['id'].to_s,
      parent_id: comment['parent_id']&.to_s, from_id: comment.dig('from', 'id')&.to_s, from_name: comment.dig('from', 'username'),
      text: comment['text'], created_time: Time.zone.at(Integer(time.to_s))
    }
  end
end
