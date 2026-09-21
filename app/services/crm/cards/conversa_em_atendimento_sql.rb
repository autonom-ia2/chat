# A CONVERSA EM ATENDIMENTO, EM SQL — o mesmo que `Crm::Card#conversa_em_atendimento` escolhe em
# Ruby, para quem precisa filtrar em lote.
#
# Enquanto o filtro do quadro lia só `crm_cards.conversation_id`, filtrar por "responsável: fulano"
# PERDIA os cards escalados: desde a issue #553 o responsável entra na conversa viva, e a primária
# é a primeira conversa daquele cliente (issue #555).
#
# A ordem espelha o Ruby, e precisa espelhar: viva na frente (aberta ou pendente), entre as vivas a
# de atividade mais recente com o `id` desempatando, e a primária como último recurso quando
# nenhuma está de pé. Duas regras que divergem são pior do que uma errada: a tela mostraria um
# responsável e o filtro procuraria outro.
module Crm::Cards::ConversaEmAtendimentoSql
  def self.join
    <<~SQL.squish

      LEFT JOIN LATERAL (
        SELECT c.* FROM conversations c
        WHERE c.id = crm_cards.conversation_id
           OR c.id IN (SELECT ccc.conversation_id FROM crm_card_conversations ccc WHERE ccc.card_id = crm_cards.id)
        ORDER BY (c.status IN (0, 2)) DESC,
                 CASE WHEN c.status IN (0, 2) THEN c.last_activity_at END DESC NULLS LAST,
                 CASE WHEN c.status IN (0, 2) THEN c.id END DESC NULLS LAST,
                 (c.id = crm_cards.conversation_id) DESC
        LIMIT 1
      ) conversations ON TRUE
    SQL
  end
end
