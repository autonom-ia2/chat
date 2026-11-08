# Webhook `feed` da Página (#2197). O roteador do POST /bot (infra #2200) entrega aqui cada `changes[]` de campo
# `feed`. Tudo da Página chega (post, curtida, comentário, o eco das respostas da própria Página); só comentário novo
# de outra pessoa interessa (Crm::MetaAds::FacebookFeed).
#
# Só os ids entram nos argumentos (`webhook_value`, chamado pelo roteador): o texto e o nome de quem comentou são lidos
# na Graph pelo FacebookFeed, para não ficarem em claro no Redis do Sidekiq nem no log do job.
class Webhooks::FacebookFeedJob < ApplicationJob
  queue_as :default
  self.log_arguments = false

  ID_FIELDS = %w[item verb post_id comment_id parent_id created_time].freeze

  def self.webhook_value(value)
    return {} unless value.is_a?(Hash)

    value = value.deep_stringify_keys
    from = value['from'].is_a?(Hash) ? value['from'] : {}
    value.slice(*ID_FIELDS).merge('from_id' => from['id']&.to_s).compact
  end

  def perform(page_id, value, _time = nil)
    Crm::MetaAds::FacebookFeed.new(page_id.to_s, value).perform
  end
end
