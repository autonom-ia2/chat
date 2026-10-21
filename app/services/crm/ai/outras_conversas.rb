# As mensagens de outras conversas dos cards da avaliação conjunta (#1693; outro canal, #1664: e-mail + WhatsApp).
#
# A avaliação de um card lê as mensagens recentes de TODAS as conversas dele (Crm::Ai::ContextBuilder#recent_messages,
# na janela da avaliação: até MAX_MESSAGES_CAP no total, divididas entre as conversas, #1926). Na conjunta, a conversa comum é o recorte do
# principal; de cada outro card vai, no pacote dele, o que o recorte dele traz e a conversa comum não tem. O limite é
# por card (MAX_POR_CARD, as mais recentes dele) e por chamada (MAX_TOTAL, as mais recentes entre todos os cards).
#
#   Crm::Ai::OutrasConversas.por_card(classificadores) # => { card_id => [mensagens, da mais antiga à mais nova] }
#
# A mesma mensagem nos dois recortes se reconhece por papel, texto, hora e conversa. O conversation_id só vem escrito
# quando o card tem mais de uma conversa; com uma só, a conversa é a dele. Assim, textos iguais no mesmo segundo em
# canais diferentes continuam sendo duas mensagens.
#
# Revisão de segurança: na chamada conjunta os pacotes se veem. De cada card entram a conversa primária dele (como na
# avaliação de um card só) e as vinculadas que chegam por uma caixa que alimenta o funil dele; uma conversa vinculada
# de um canal que o funil não atende não vai para a chamada.
class Crm::Ai::OutrasConversas
  # #1926: o recorte que a avaliação do card lê de uma conversa quando ele tem duas (a comum e a do outro canal, o caso
  # da conjunta). Com 12, a proposta antiga do outro canal, que a avaliação do card sozinho já via, sumia aqui.
  MAX_POR_CARD = Crm::Ai::ContextBuilder.janela_da_avaliacao(2)
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
    permitidas = cards.dig(id(classificador), :permitidas).to_a
    proprias = mensagens(classificador).select { |_mensagem, chave| permitidas.include?(chave[:conversation_id]) && vistas.exclude?(chave) }
                                       .last(MAX_POR_CARD)
    proprias.map { |mensagem, _chave| [id(classificador), mensagem] }
  end

  # Ordem estável: na mesma hora, vale a ordem dos cards.
  def mais_recentes(candidatas)
    candidatas.each_with_index.sort_by { |(_card, mensagem), ordem| [mensagem[:created_at].to_s, ordem] }
              .last(MAX_TOTAL).map(&:first)
  end

  def mensagens(classificador)
    unica = cards.dig(id(classificador), :unica)
    Array(classificador.conversa[:recent_messages]).map do |mensagem|
      [mensagem, mensagem.slice(:role, :content, :created_at).merge(conversation_id: mensagem[:conversation_id] || unica)]
    end
  end

  def id(classificador)
    classificador.pacote.dig(:card, :id)
  end

  # Uma leitura para todos os cards, nas mesmas conversas que o ContextBuilder lê (a primária e as vinculadas):
  # { card_id => { unica: a conversa, se é uma só; permitidas: a primária e as vinculadas de caixas do funil } }.
  def cards
    @cards ||= linhas.to_h { |card_id, pipeline_id, primaria| [card_id, conversas_do_card(card_id, pipeline_id, primaria)] }
  end

  def ids
    @classificadores.map { |classificador| id(classificador) }
  end

  def linhas
    @linhas ||= Crm::Card.where(id: ids).pluck(:id, :pipeline_id, :conversation_id)
  end

  def conversas_do_card(card_id, pipeline_id, primaria)
    ligadas = vinculos.filter_map { |card, conversa| conversa if card == card_id }
    todas = [primaria, *ligadas].compact.uniq
    do_funil = ligadas.select { |conversa| caixas_do_funil[pipeline_id].to_a.include?(caixa_da_conversa[conversa]) }
    { unica: (todas.first if todas.one?), permitidas: [primaria, *do_funil].compact }
  end

  def vinculos
    @vinculos ||= Crm::CardConversation.where(card_id: ids).pluck(:card_id, :conversation_id)
  end

  def caixa_da_conversa
    @caixa_da_conversa ||= Conversation.where(id: vinculos.map(&:last)).pluck(:id, :inbox_id).to_h
  end

  def caixas_do_funil
    @caixas_do_funil ||= Crm::PipelineInbox.where(pipeline_id: linhas.map(&:second)).pluck(:pipeline_id, :inbox_id)
                                           .group_by(&:first).transform_values { |pares| pares.map(&:last) }
  end
end
