# O alvo de uma execução e as pontes dele (#2499, F6): a conversa, o card ou o contato em que a automação roda, e os
# outros dois quando há caminho até eles. O Valores, os passos e o Spam leem por aqui, nunca supondo a conversa.
#
# | alvo     | conversa                             | card | contato           |
# | conversa | ela                                  | —    | conversa.contact  |
# | card     | card.primary_conversation (pode faltar) | ele | card.contact, senão o da conversa |
# | contato  | —                                    | —    | ele               |
#
# Contrato com a F2 (#2498, histórico e ensaio): `rotulo`, `link` e `visivel_para?(usuario)`. O rótulo sai do i18n e do
# registro na hora, nunca é gravado.
class Autonomia::Automacao::Contexto
  TIPOS = %w[Conversation Crm::Card Contact].freeze

  attr_reader :alvo, :execucao

  # `execucao`: a execução em que o passo roda, quando há uma. A reunião do gatilho (G12), o texto da IA (#2679) e o
  # "gatilho repetiu" (lote 4) leem dela.
  # `textos`: no ensaio, que não tem execução, o texto que cada passo de IA produziria (só para mostrar).
  def self.de(alvo, execucao: nil, textos: nil) = new(alvo, execucao: execucao, textos: textos)

  # Os `textos` do ensaio (#2679): ele não chama a IA, e no lugar do texto de cada passo que escreve vai a marca de onde
  # ele entraria.
  def self.marcas_da_ia(receita, conta)
    ::Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: nil).passos
                                   .select { |passo| ::Autonomia::Automacao::Valores::PASSOS_QUE_ESCREVEM.include?(passo['tipo']) }
                                   .to_h { |passo| [passo['id'], I18n.t('autonomia.automacao.ensaio.texto_da_ia', passo: passo['id'])] }
  end

  def initialize(alvo, execucao: nil, textos: nil)
    @alvo = alvo
    @execucao = execucao
    @textos = textos
  end

  def conversa
    return @alvo if @alvo.is_a?(::Conversation)

    @alvo.primary_conversation if @alvo.is_a?(::Crm::Card)
  end

  def card = (@alvo if @alvo.is_a?(::Crm::Card))

  def contato
    return @alvo if @alvo.is_a?(::Contact)
    return @alvo.contact if @alvo.is_a?(::Conversation)

    @alvo.contact || conversa&.contact if @alvo.is_a?(::Crm::Card)
  end

  # A reunião do gatilho de reunião (G12): a da atividade que disparou, achada pela marca da execução e sempre presa ao
  # card e à conta do alvo (parecer do Funções), nunca só pelo id. Num passo que roda dias depois ela é relida: a
  # reunião remarcada de novo traz o horário novo. Fora do gatilho de reunião, ou sem a atividade, nil.
  def reuniao
    return @reuniao if defined?(@reuniao)

    @reuniao = (reuniao_da_atividade if card && @execucao && ::Autonomia::Automacao::Gatilhos.de_reuniao?(@execucao.chave_gatilho))
  end

  # #2679: o texto que o passo de IA `passo_id` produziu nesta execução (Execucao#guardar_texto!). Antes do passo rodar,
  # nil.
  def texto_da_ia(passo_id) = (@textos || @execucao&.textos).to_h[passo_id.to_s]

  # "conversa", "card" ou "contato": a base dos caminhos do Valores que o alvo tem sem ponte.
  def base
    { ::Conversation => 'conversa', ::Crm::Card => 'card', ::Contact => 'contato' }.find { |classe, _| @alvo.is_a?(classe) }&.last
  end

  # O Spam (F3.5) vale para a conversa, para a conversa principal do card e para o contato cuja única conversa está lá.
  def no_spam?
    return ::ConversaCanal::PastaDoEmail.no_spam?(conversa) if conversa
    return false unless @alvo.is_a?(::Contact)

    conversas = ::Conversation.where(account_id: @alvo.account_id, contact_id: @alvo.id).limit(2).to_a
    conversas.one? && ::ConversaCanal::PastaDoEmail.no_spam?(conversas.first)
  end

  def rotulo
    case @alvo
    when ::Conversation then I18n.t('autonomia.automacao.alvo.conversa', id: @alvo.display_id)
    when ::Crm::Card then I18n.t('autonomia.automacao.alvo.card', id: @alvo.id, titulo: @alvo.title)
    when ::Contact then I18n.t('autonomia.automacao.alvo.contato', nome: @alvo.name.presence || @alvo.id)
    end
  end

  def link
    conta = @alvo.account_id
    case @alvo
    when ::Conversation then "accounts/#{conta}/conversations/#{@alvo.display_id}"
    when ::Crm::Card then "accounts/#{conta}/crm?pipeline_id=#{@alvo.pipeline_id}&card_id=#{@alvo.id}"
    when ::Contact then "accounts/#{conta}/contacts/#{@alvo.id}"
    end
  end

  # A mesma pergunta que a leitura faria: a política da conversa (view?, que no EE também deixa quem só lê,
  # conversation_view), a do card ou a do contato. Para agir no alvo, a pergunta é a do Acesso#alcanca?.
  def visivel_para?(usuario)
    account_user = usuario && @alvo.account.account_users.find_by(user_id: usuario.id)
    return false unless account_user

    contexto = { user: usuario, account: @alvo.account, account_user: account_user }
    case @alvo
    when ::Conversation then ConversationPolicy.new(contexto, @alvo).view?
    when ::Crm::Card then ::Crm::CardPolicy.new(contexto, @alvo).show?
    when ::Contact then ContactPolicy.new(contexto, @alvo).show?
    else false
    end
  end

  private

  def reuniao_da_atividade
    atividade_id = ::Autonomia::Automacao::Gatilhos.atividade_da_marca(@execucao.evento)
    atividade = atividade_id && ::Crm::Activity.find_by(id: atividade_id, account_id: card.account_id, card_id: card.id)
    reuniao_id = atividade&.payload.to_h['meeting_id']
    reuniao_id && card.account.crm_meetings.find_by(id: reuniao_id, card_id: card.id)
  end
end
