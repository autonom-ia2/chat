# Uma página de comentários do Instagram como a Graph do login do Instagram devolve, arrumada em fios (#2313).
#
# A Graph devolve a resposta da própria conta duas vezes (visto em produção): em primeiro nível, com o `from` da conta,
# e dentro do comentário respondido, sem `from`. Fica só a de dentro, onde ela está no app; a cópia de cima é o que diz
# que ela é da conta. A Graph do login do Facebook, para a mesma mídia, traz a resposta só dentro do comentário.
class Crm::MetaAds::InstagramCommentThreads
  def initialize(rows, instagram_id)
    @rows = rows
    @instagram_id = instagram_id.to_s
  end

  def top
    nested = ids_of(@rows.flat_map { |item| replies(item) })
    @rows.reject { |item| nested.include?(item['id'].to_s) }
  end

  def replies(item)
    Array(item.dig('replies', 'data'))
  end

  # Todos os ids da página, de comentário e de resposta.
  def ids
    ids_of(@rows + @rows.flat_map { |item| replies(item) }).to_a
  end

  def own?(item)
    item.dig('from', 'id').to_s == @instagram_id || own_ids.include?(item['id'].to_s)
  end

  private

  def own_ids
    @own_ids ||= ids_of(@rows.select { |item| item.dig('from', 'id').to_s == @instagram_id })
  end

  def ids_of(items)
    items.to_set { |item| item['id'].to_s }
  end
end
