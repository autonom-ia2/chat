# Comentário novo no Instagram (#2196): o campo `comments` do webhook do login do Instagram, que o roteador do webhook
# (Webhooks::InstagramEventsJob#enqueue_comment, infra #2200) manda para cá.
#
# Contrato único: `perform(instagram_id, field, value_ids, time)`, com o `entry.id`, o campo, os ids do `value` (`id`,
# `parent_id`, `from.id`, `media.id`, `media.ad_id`) e o `entry.time`. O texto e o username de quem comentou são lidos
# na Graph aqui, com o token da caixa, para não ficarem nos argumentos do job (fila, retry e dead set do Sidekiq guardam
# os argumentos em claro no Redis).
# TRANSIÇÃO (#2291, prazo 15/11/2026): o `value` completo do webhook, com texto, de antes do deploy do #2287, ainda é
# aceito; daqui só os ids são usados.
#
# Vira o evento comum `meta_ads.comment_received` para quem cuida dos comentários (#2212), só com ids: sem o texto e
# sem o username (#2327). O Dispatcher passa o payload ao EventDispatcherJob, cujos argumentos ficam no Redis e podem
# sair no log; quem consome lê o texto e o autor pelo Instagram::CommentsClient. A leitura na Graph daqui continua: é
# ela que separa o eco da própria conta. Ficam de fora: outros
# campos (`mentions`), o eco das respostas da própria conta, Instagram sem caixa na plataforma (o relay entre stacks
# entrega o mesmo corpo às duas; cada uma só publica o que é dela), conta sem a flag `meta_ads_comentarios_instagram`
# (sem ela a caixa não tem a permissão de ler comentários) e o mesmo comentário de novo em DEDUP (webhook reenviado).
# A chave do dedupe é gravada antes da leitura na Graph e só fica se o evento saiu: qualquer outro desfecho a solta, e o
# retry ou o reenvio leem de novo. Nada do
# comentário é gravado aqui. Ids fora do formato são descartados em silêncio; Graph fora do ar sobe para o retry.
class Webhooks::InstagramCommentJob < ApplicationJob
  queue_as :default
  self.log_arguments = false

  DEDUP = 10.minutes

  def perform(instagram_id, field, value, time)
    return unless field == 'comments' && value.is_a?(Hash)

    ids = ids(value)
    return unless valid?(ids, time) && ids[:from_id] != instagram_id.to_s

    channel = channel_for(instagram_id)
    return if channel.nil? || !first_time?(instagram_id, ids[:comment_id])

    publish(channel, instagram_id, ids, time)
  end

  private

  def ids(value)
    value = value.with_indifferent_access
    media = value[:media].is_a?(Hash) ? value[:media] : {}
    from = value[:from].is_a?(Hash) ? value[:from] : {}
    { comment_id: value[:id]&.to_s, ad_id: media[:ad_id].presence&.to_s, from_id: from[:id]&.to_s }
  end

  def valid?(ids, time)
    digits?(ids[:comment_id]) && (ids[:ad_id].nil? || digits?(ids[:ad_id])) && Integer(time.to_s, exception: false).present?
  end

  def digits?(value)
    value.present? && value.each_char.all? { |char| char.between?('0', '9') }
  end

  def channel_for(instagram_id)
    channel = Channel::Instagram.find_by(instagram_id: instagram_id.to_s)
    channel if channel&.inbox.present? && channel.account.feature_enabled?('meta_ads_comentarios_instagram')
  end

  # A chave do dedupe só fica se o evento saiu: em qualquer outro desfecho (sem resultado, eco, erro, desligamento do
  # Sidekiq) o `ensure` a solta.
  def publish(channel, instagram_id, ids, time)
    dispatched = false
    comment = read_comment(channel, ids[:comment_id])
    return if comment.nil? || comment.dig('from', 'id').to_s == instagram_id.to_s

    Rails.configuration.dispatcher.dispatch(Events::Types::META_ADS_COMMENT_RECEIVED, Time.zone.now,
                                            payload(channel, comment, time, ids[:ad_id]))
    dispatched = true
  ensure
    release(instagram_id, ids[:comment_id]) unless dispatched
  end

  def dedup_key(instagram_id, comment_id)
    "instagram:comment_received:#{instagram_id}:#{comment_id}"
  end

  def first_time?(instagram_id, comment_id)
    Redis::Alfred.set(dedup_key(instagram_id, comment_id), 1, nx: true, ex: DEDUP.to_i) ? true : false
  end

  def release(instagram_id, comment_id)
    Redis::Alfred.delete(dedup_key(instagram_id, comment_id))
    nil
  end

  def read_comment(channel, comment_id)
    result = Instagram::CommentsClient.new(channel).comment(comment_id)
    return result.data if result.ok
    raise Instagram::CommentsClient::Unavailable, comment_id if result.transient?

    nil
  end

  def payload(channel, comment, time, ad_id)
    {
      network: 'instagram', account_id: channel.account_id, inbox_id: channel.inbox.id, instagram_id: channel.instagram_id,
      media_id: comment.dig('media', 'id')&.to_s, ad_id: ad_id, comment_id: comment['id'].to_s,
      parent_id: comment['parent_id']&.to_s, from_id: comment.dig('from', 'id')&.to_s, created_time: Time.zone.at(Integer(time.to_s))
    }
  end
end
