# Vários assuntos numa mensagem (#1693, flag `crm_avaliar_toda_mensagem`): depois da decisão do assunto, a IA do CRM
# avalia os cards que a mensagem tocou, numa chamada só (Crm::Ai::EvaluateCardsJob). Herda do CardEmFoco (#1675) as
# guardas (flag, IA do CRM, mensagem do cliente, CRM da caixa), a hora em que o texto ficou disponível (também a do
# WhatsApp Híbrido, #1638) e o registro da atividade, só para a frente.
#
# A lista vem da decisão (Crm::SubjectDecision#touched_card_ids, o principal primeiro):
#   - nula: a IA de assunto não chegou a uma lista (dúvida, falha, sem cota, decisão reaberta). Fica como no #1675: a IA
#     relê o card em foco;
#   - vazia: não há card a reler. Sem assunto com card em foco já vem com ele na lista (#1918); vazia fica para a
#     conversa sem card aberto e para o pedido novo que virou sugestão (pendente, dispensada ou repetida, #1147). Nada
#     é avaliado; o card em foco, se houver, só guarda a hora da última mensagem (a atividade não anda, senão o
#     StaleCardsJob o reavaliaria por isso);
#   - com cards: cada card aberto da lista conta a mensagem como atividade e recebe o mesmo token de agendamento, que
#     deixa velha qualquer avaliação dele agendada antes (a troca de foco e o card novo da mesma mensagem): uma
#     mensagem, uma chamada. Se todos já têm avaliação agendada depois da mensagem (retry do IdentifyJob, ou a troca de
#     foco de um assunto só) para rodar dentro do debounce do cliente, não agenda de novo; a avaliação da mensagem da
#     equipe (#1923), mais longa, não conta, senão o cliente esperaria a espera dela.
# O principal é o card da decisão; com o principal em dúvida (#1693, C27), o card em foco, se a mensagem o tocou. É nele
# que a IA põe o pedido de atendente que o cliente não ligou a nenhum assunto.
class Crm::Conversations::CardsTocados < Crm::Conversations::CardEmFoco
  def perform
    decisao = Crm::SubjectDecision.find_by(conversation_id: @conversation.id, message_id: @message.id)
    return super if decisao&.touched_card_ids.nil?
    return [] unless mensagem_do_cliente?

    cards = abertos(decisao.touched_card_ids)
    cards.empty? ? so_a_mensagem : tocar(cards, decisao.card_id)
  end

  private

  def abertos(ids)
    @account.crm_cards.open.where(id: ids).index_by(&:id).values_at(*ids).compact
  end

  def tocar(cards, principal_id)
    cards.each { |card| avisar(card) if registrar_atividade(card) }
    agendar(cards, principal_id) unless cards.all? { |card| Crm::Ai::Observer.new(card: card).agendada_para_o_cliente?(chegada) }
    cards
  end

  # O job entra na fila antes das marcas: se uma marca falhar no meio, os cards sem a marca nova seguem com o token
  # antigo, e o job (que só pula card com token MAIS NOVO que o dele) os avalia mesmo assim.
  def agendar(cards, principal_id)
    token = Time.current.to_f
    ids = cards.map(&:id)
    Crm::Ai::EvaluateCardsJob.set(wait: Crm::Ai::Config::DEBOUNCE_SECONDS.seconds).perform_later(ids, principal(ids, principal_id), token)
    cards.each { |card| Crm::Ai::Observer.new(card: card).marcar(token) }
  end

  def principal(ids, principal_id)
    return principal_id if ids.include?(principal_id)

    foco = Crm::Assunto.funil_atual(@conversation)&.id
    foco if ids.include?(foco)
  end

  def so_a_mensagem
    card = Crm::Assunto.funil_atual(@conversation)
    avisar(card) if card && registrar_mensagem(card)
    []
  end

  def registrar_mensagem(card)
    cards = Crm::Card.where(id: card.id)
    cards.where(last_message_at: nil).or(cards.where(last_message_at: ...@message.created_at))
         .update_all(last_message_at: @message.created_at).positive? # rubocop:disable Rails/SkipsModelValidations
  end

  def avisar(card)
    Crm::Cards::Broadcaster.broadcast(card.reload, Events::Types::CRM_CARD_UPDATED)
  end
end
