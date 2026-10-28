# Uma página de comentários do Instagram como a Graph do login do Instagram devolve, arrumada em fios (#2313).
#
# A Graph devolve a resposta da própria conta duas vezes (visto em produção): em primeiro nível, com o `from` da conta,
# e dentro do comentário respondido, sem `from`. A Graph do login do Facebook, para a mesma mídia, traz a resposta só
# dentro do comentário. Então:
# - fica só a cópia de dentro, onde ela está no app: sai de cima o item que tem `parent_id` (o pai pode estar em outra
#   página) ou que aparece dentro de um comentário desta página;
# - a cópia de dentro sem `from` herda o da cópia de cima, quando ela veio na página;
# - `own_ids`: as respostas que o painel publicou (Crm::MetaAdsCommentAction `reply`), da conta mesmo sem `from`.
class Crm::MetaAds::InstagramCommentThreads
  # Com as respostas que o painel publicou nesta página, gravadas na conta.
  def self.build(rows, channel, account_id)
    ids = rows.flat_map { |item| [item['id'], *Array(item.dig('replies', 'data')).pluck('id')] }.map(&:to_s)
    own_ids = Crm::MetaAdsCommentAction.where(account_id: account_id, network: 'instagram', action: 'reply', comment_id: ids)
                                       .pluck(:comment_id)
    new(rows, channel.instagram_id, own_ids: own_ids)
  end

  def initialize(rows, instagram_id, own_ids: [])
    @rows = rows
    @instagram_id = instagram_id.to_s
    @own_ids = own_ids.to_set(&:to_s)
  end

  def top
    @rows.reject { |item| item['parent_id'].present? || nested_ids.include?(item['id'].to_s) }
  end

  def replies(item)
    Array(item.dig('replies', 'data')).map { |reply| reply['from'] ? reply : reply.merge('from' => copy_from[reply['id'].to_s]).compact }
  end

  # Todos os ids da página, de comentário e de resposta, sem repetir.
  def ids
    (@rows.map { |item| item['id'].to_s } + nested_ids.to_a).uniq
  end

  def own?(item)
    item.dig('from', 'id').to_s == @instagram_id || @own_ids.include?(item['id'].to_s)
  end

  private

  def nested_ids
    @nested_ids ||= @rows.flat_map { |item| Array(item.dig('replies', 'data')) }.to_set { |reply| reply['id'].to_s }
  end

  # O `from` das cópias de cima, pelo id.
  def copy_from
    @copy_from ||= @rows.select { |item| item['from'] }.to_h { |item| [item['id'].to_s, item['from']] }
  end
end
