# As conversas da ficha de Relacionamentos (#2895) no formato da tela: o número que o painel usa para abrir a conversa, o
# canal, um trecho da última mensagem que alguém escreveu (da pessoa ou de quem atende), quando ela andou pela última
# vez e a situação em palavra. Aviso de atividade, mensagem automática da caixa (pedir e-mail, pesquisa) e nota interna da
# equipe não são trecho: ele é o que foi dito na conversa com a pessoa.
# Recebe as conversas que quem pede pode ler (Contacts::ConversasLegiveis); na ficha da empresa cada uma diz de quem é.
class Relacionamentos::Ficha::Conversas
  # A tela mostra as 3 últimas e leva ao histórico em "Ver todas". O teto é a página do histórico do contato de hoje
  # (Contacts::ConversationsController::RESULTS_PER_PAGE).
  TETO = 25
  # O trecho ocupa uma ou duas linhas na tela; um e-mail inteiro não precisa viajar.
  TRECHO = 240
  SITUACOES = { 'open' => 'aberta', 'pending' => 'pendente', 'resolved' => 'resolvida', 'snoozed' => 'adiada' }.freeze
  ESCRITAS_POR_ALGUEM = %i[incoming outgoing].freeze
  ULTIMA_DE_CADA = 'DISTINCT ON (messages.conversation_id) messages.conversation_id, messages.content'.freeze

  def initialize(conversas, com_pessoa: false)
    @conversas = conversas
    @com_pessoa = com_pessoa
  end

  def call
    conversas = @conversas.order(last_activity_at: :desc, id: :desc).limit(TETO).preload(*do_que_a_linha_usa).to_a
    trechos = trechos_de(conversas)
    conversas.map { |conversa| linha(conversa, trechos[conversa.id]) }
  end

  private

  def do_que_a_linha_usa
    @com_pessoa ? [{ inbox: :channel }, :contact] : [{ inbox: :channel }]
  end

  # A última mensagem de cada conversa numa consulta só.
  def trechos_de(conversas)
    Message.where(conversation_id: conversas.map(&:id), message_type: ESCRITAS_POR_ALGUEM, private: false)
           .reorder(:conversation_id, created_at: :desc, id: :desc).select(ULTIMA_DE_CADA)
           .to_h { |mensagem| [mensagem.conversation_id, mensagem.content] }
  end

  def linha(conversa, trecho)
    linha = { id: conversa.display_id, canal: Relacionamentos::Ficha::Canal.de(conversa.inbox), trecho: trecho&.truncate(TRECHO),
              quando: conversa.last_activity_at.to_i, situacao: SITUACOES.fetch(conversa.status) }
    @com_pessoa ? linha.merge(pessoa: conversa.contact.name) : linha
  end
end
