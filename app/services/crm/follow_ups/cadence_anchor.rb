# De onde a cadência conta as horas. O intervalo do funil ("6h", "48h") é medido a partir da
# ÚLTIMA MENSAGEM REAL da conversa — do cliente, de uma pessoa do time ou de um bot — e não mais
# só da última fala do cliente.
#
# O motivo: com a âncora presa ao cliente, o time podia estar conversando com ele agora e o toque
# automático disparava por cima, porque o relógio tinha começado a correr horas antes e nada do
# que o time escrevia movia esse relógio.
#
# Duas exclusões, e as duas importam:
#   * o próprio follow-up automático (content_attributes['crm_follow_up_id']) NÃO conta. Se
#     contasse, cada toque viraria a âncora do seguinte e o espaçamento configurado mudaria
#     sozinho: com [6, 48] o toque 2 sairia 48h depois do toque 1, em vez das 42h que o funil
#     pediu. A IA não pode reescrever a régua que o usuário configurou.
#   * nota privada e evento de sistema (activity) não são conversa com o cliente.
#
# Planner e runner usam esta mesma classe de propósito: foi cópia divergente da mesma regra que
# já produziu bug antes neste subsistema.
class Crm::FollowUps::CadenceAnchor
  # O descarte dos toques da IA é feito em Ruby, não em SQL. `content_attributes` é coluna json
  # com `store ... coder: JSON` no Message: o Rails grava o hash como STRING JSON dentro do json
  # ("{\"crm_follow_up_id\":1}"), então `content_attributes ->> 'chave'` devolve sempre NULL e um
  # filtro SQL desses não exclui nada — falha silenciosa, que é o pior tipo.
  # A varredura é limitada porque a cadência tem no máximo um punhado de toques seguidos; se
  # todos os SCAN_LIMIT mais recentes forem da IA, não há âncora útil ali.
  SCAN_LIMIT = 20

  def initialize(conversation)
    @conversation = conversation
  end

  # -> Time ou nil (conversa ausente ou sem nenhuma mensagem que conte)
  def at
    return nil if @conversation.blank?

    @conversation.messages
                 .where(private: false)
                 .where.not(message_type: :activity)
                 .reorder(id: :desc)
                 .limit(SCAN_LIMIT)
                 .find { |message| message.content_attributes.to_h['crm_follow_up_id'].blank? }
                 &.created_at
  end
end
