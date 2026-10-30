# IA cuida dos comentários (#2212): o comentário novo como chega no evento `meta_ads.comment_received`, publicado pelo
# #2196 (Instagram) e pelo #2197 (Facebook) com o mesmo contrato. As duas redes chamam o dono e o post por nomes
# diferentes (instagram_id/media_id, page_id/post_id); aqui viram `owner_id` e `post_id`.
#
# O evento leva só ids (#2327): o texto e o nome de quem comentou são dado de terceiro e não podem ir para o Redis nem
# para o log, onde ficam os argumentos do EventDispatcherJob e do CuidarJob. O Cuidar os lê na Meta na hora (Rede#ler) e
# os põe numa cópia (`lido`), que segue até a conversa que nasce do comentário. Nada disso fica em tabela própria.
Crm::MetaAds::ComentariosIa::Comentario = Struct.new(
  :network, :account_id, :inbox_id, :owner_id, :post_id, :ad_id, :comment_id, :parent_id, :from_id, :from_name, :text,
  :created_time,
  keyword_init: true
) do
  def self.do_evento(data)
    dados = data.to_h.with_indifferent_access
    new(network: dados[:network], account_id: dados[:account_id], inbox_id: dados[:inbox_id],
        owner_id: dados[:instagram_id] || dados[:page_id], post_id: dados[:media_id] || dados[:post_id], ad_id: dados[:ad_id],
        comment_id: dados[:comment_id], parent_id: dados[:parent_id], from_id: dados[:from_id], created_time: dados[:created_time])
  end

  # Para o job: só ids e valores simples (o ActiveJob não serializa Struct). A hora pode chegar como Time ou como texto.
  def para_o_job
    to_h.except(:text, :from_name).merge(created_time: momento&.iso8601)
  end

  # O mesmo comentário, com o texto e o nome lidos na Meta.
  def lido(text:, from_name:)
    self.class.new(**to_h, text: text, from_name: from_name)
  end

  def resposta?
    parent_id.present?
  end

  def momento
    created_time.is_a?(String) ? Time.zone.parse(created_time) : created_time
  rescue ArgumentError
    nil
  end
end
