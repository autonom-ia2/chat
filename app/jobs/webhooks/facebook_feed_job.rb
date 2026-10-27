# Webhook `feed` da Página (#2197). O roteador do POST /bot (infra #2200) entrega aqui cada `changes[]` de campo
# `feed`: `value` é o que a Meta mandou, sem mexer. Tudo da Página chega (post, curtida, comentário, o eco das
# respostas da própria Página); só comentário novo de outra pessoa interessa (Crm::MetaAds::FacebookFeed).
class Webhooks::FacebookFeedJob < ApplicationJob
  queue_as :default

  def perform(page_id, value, _time = nil)
    Crm::MetaAds::FacebookFeed.new(page_id.to_s, value).perform
  end
end
