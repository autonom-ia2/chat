# As mensagens de outras conversas dos cards da avaliação conjunta (#1693; outro canal, #1664: e-mail + WhatsApp).
#
# A avaliação de um card lê as mensagens recentes de TODAS as conversas dele (Crm::Ai::ContextBuilder#recent_messages,
# até MAX_RECENT_MESSAGES por conversa e MAX_MESSAGES_CAP no total). Na conjunta, a conversa comum é o recorte do
# principal; de cada outro card vai, no pacote dele, o que o recorte dele traz e a conversa comum não tem. O limite é
# por card (MAX_POR_CARD, as mais recentes dele) e por chamada (MAX_TOTAL, as mais recentes entre todos os cards).
#
#   Crm::Ai::OutrasConversas.por_card(classificadores) # => { card_id => [mensagens, da mais antiga à mais nova] }
#
# A mesma mensagem nos dois recortes se reconhece por papel, texto, hora e conversa. O conversation_id só vem escrito
# quando o card tem mais de uma conversa; com uma só, a conversa é a dele. Assim, textos iguais no mesmo segundo em
# canais diferentes continuam sendo duas mensagens.
class Crm::Ai::OutrasConversas
  MAX_POR_CARD = Crm::Ai::ContextBuilder::MAX_RECENT_MESSAGES
  MAX_TOTAL = Crm::Ai::ContextBuilder::MAX_MESSAGES_CAP

  # classificadores: um StageClassifier por card, o principal primeiro.
  def self.por_card(classificadores)
    new(classificadores).por_card
  end

  def initialize(classificadores)
    @classificadores = classificadores
  end

  def por_card
    vistas = mensagens(@classificadores.first).map(&:last)
    candidatas = @classificadores.drop(1).flat_map { |classificador| candidatas(classificador, vistas) }
    mais_recentes(candidatas).group_by(&:first).transform_values { |pares| pares.map(&:last) }
  end

  private

  # O que o recorte do card traz e a janela do principal não tem, as mais recentes dele. Conversa ligada a dois cards
  # tocados vai nos dois pacotes (é dos dois pedidos) e conta duas vezes no limite total, que é o que segue na chamada.
  def candidatas(classificador, vistas)
    proprias = mensagens(classificador).reject { |_mensagem, chave| vistas.include?(chave) }.last(MAX_POR_CARD)
    proprias.map { |mensagem, _chave| [id(classificador), mensagem] }
  end

  # Ordem estável: na mesma hora, vale a ordem dos cards.
  def mais_recentes(candidatas)
    candidatas.each_with_index.sort_by { |(_card, mensagem), ordem| [mensagem[:created_at].to_s, ordem] }
              .last(MAX_TOTAL).map(&:first)
  end

  def mensagens(classificador)
    unica = conversas_unicas[id(classificador)]
    Array(classificador.conversa[:recent_messages]).map do |mensagem|
      [mensagem, mensagem.slice(:role, :content, :created_at).merge(conversation_id: mensagem[:conversation_id] || unica)]
    end
  end

  def id(classificador)
    classificador.pacote.dig(:card, :id)
  end

  # As mesmas conversas que o ContextBuilder lê de cada card (a primária e as vinculadas), em duas consultas para todos:
  # { card_id => conversation_id } dos cards com uma conversa só.
  def conversas_unicas
    @conversas_unicas ||= begin
      ids = @classificadores.map { |classificador| id(classificador) }
      pares = Crm::Card.where(id: ids).pluck(:id, :conversation_id) +
              Crm::CardConversation.where(card_id: ids).pluck(:card_id, :conversation_id)
      pares.select(&:last).uniq.group_by(&:first).filter_map { |card, dele| [card, dele.first.last] if dele.one? }.to_h
    end
  end
end
