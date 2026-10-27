# IA cuida dos comentários (#2212): o comentário novo como chega no evento `meta_ads.comment_received`, publicado pelo
# #2196 (Instagram) e pelo #2197 (Facebook) com o mesmo contrato. As duas redes chamam o dono e o post por nomes
# diferentes (instagram_id/media_id, page_id/post_id); aqui viram `owner_id` e `post_id`.
#
# O texto e o nome são dado de terceiro: seguem até o job e a conversa que nasce dele, e não ficam em tabela própria.
Crm::MetaAds::ComentariosIa::Comentario = Struct.new(
  :network, :account_id, :inbox_id, :owner_id, :post_id, :ad_id, :comment_id, :parent_id, :from_id, :from_name, :text,
  :created_time,
  keyword_init: true
) do
  def self.do_evento(data)
    dados = data.to_h.with_indifferent_access
    new(network: dados[:network], account_id: dados[:account_id], inbox_id: dados[:inbox_id],
        owner_id: dados[:instagram_id] || dados[:page_id], post_id: dados[:media_id] || dados[:post_id], ad_id: dados[:ad_id],
        comment_id: dados[:comment_id], parent_id: dados[:parent_id], from_id: dados[:from_id], from_name: dados[:from_name],
        text: dados[:text], created_time: dados[:created_time])
  end

  # Para o job: só valores simples (o ActiveJob não serializa Struct).
  def para_o_job
    to_h.merge(created_time: created_time&.iso8601)
  end

  def resposta?
    parent_id.present?
  end

  def momento
    created_time.is_a?(String) ? Time.zone.parse(created_time) : created_time
  end
end
