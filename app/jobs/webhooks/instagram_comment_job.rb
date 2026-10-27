# Comentário novo no Instagram (#2196): o campo `comments` do webhook do login do Instagram, que o roteador do webhook
# (Webhooks::InstagramEventsJob, infra #2200) manda para cá.
#
# Contrato: só ids, `perform(instagram_id, comment_id, time, ad_id = nil)` (o `entry.id`, o `value.id`, o `entry.time` e
# o `value.media.ad_id`). O texto e o username de quem comentou são lidos na Graph aqui, com o token da caixa, para não
# ficarem nos argumentos do job (fila, retry e dead set do Sidekiq guardam os argumentos em claro no Redis).
# O formato antigo `(instagram_id, field, value, time)`, com o `value` do webhook, ainda é aceito e SAI quando o
# roteador do #2200 passar ao contrato novo.
#
# Vira o evento comum `meta_ads.comment_received` para quem cuida dos comentários (#2212). Ficam de fora: o eco das
# respostas da própria conta, Instagram sem caixa na plataforma (o relay entre stacks entrega o mesmo corpo às duas;
# cada uma só publica o que é dela), conta sem a flag `meta_ads_comentarios_instagram` (sem ela a caixa não tem a
# permissão de ler comentários) e o mesmo comentário de novo em DEDUP (webhook reenviado). Nada do comentário é
# gravado aqui. Ids fora do formato são descartados em silêncio; Graph fora do ar sobe o erro para o retry.
class Webhooks::InstagramCommentJob < ApplicationJob
  queue_as :default
  self.log_arguments = false

  DEDUP = 10.minutes

  def perform(instagram_id, *args)
    comment_id, time, ad_id = args.second.is_a?(Hash) ? legacy(*args) : args
    return unless valid_ids?(comment_id, time)

    channel = channel_for(instagram_id)
    return if channel.nil? || !first_time?(instagram_id, comment_id)

    comment = read_comment(channel, instagram_id, comment_id.to_s)
    return if comment.nil? || comment.dig('from', 'id').to_s == instagram_id.to_s

    Rails.configuration.dispatcher.dispatch(Events::Types::META_ADS_COMMENT_RECEIVED, Time.zone.now,
                                            payload(channel, comment, time, ad_id))
  end

  private

  # (field, value, time) do roteador antigo: só `comments`, e do `value` só os ids.
  def legacy(field, value, time)
    return [] unless field == 'comments'

    [value['id'], time, value.dig('media', 'ad_id')]
  end

  def valid_ids?(comment_id, time)
    digits?(comment_id) && Integer(time.to_s, exception: false).present?
  end

  def digits?(value)
    value.present? && value.to_s.each_char.all? { |char| char.between?('0', '9') }
  end

  def channel_for(instagram_id)
    channel = Channel::Instagram.find_by(instagram_id: instagram_id.to_s)
    channel if channel&.inbox.present? && channel.account.feature_enabled?('meta_ads_comentarios_instagram')
  end

  def dedup_key(instagram_id, comment_id)
    "instagram:comment_received:#{instagram_id}:#{comment_id}"
  end

  def first_time?(instagram_id, comment_id)
    Redis::Alfred.set(dedup_key(instagram_id, comment_id), 1, nx: true, ex: DEDUP.to_i) ? true : false
  end

  # Graph fora do ar: solta o dedupe antes de subir, para o retry ler de novo.
  def read_comment(channel, instagram_id, comment_id)
    result = Instagram::CommentsClient.new(channel).comment(comment_id)
    return result.data if result.ok
    return unless result.transient?

    Redis::Alfred.delete(dedup_key(instagram_id, comment_id))
    raise Instagram::CommentsClient::Unavailable, comment_id
  end

  def payload(channel, comment, time, ad_id)
    {
      network: 'instagram', account_id: channel.account_id, inbox_id: channel.inbox.id, instagram_id: channel.instagram_id,
      media_id: comment.dig('media', 'id')&.to_s, ad_id: ad_id.presence&.to_s, comment_id: comment['id'].to_s,
      parent_id: comment['parent_id']&.to_s, from_id: comment.dig('from', 'id')&.to_s, from_name: comment.dig('from', 'username'),
      text: comment['text'], created_time: Time.zone.at(Integer(time.to_s))
    }
  end
end
