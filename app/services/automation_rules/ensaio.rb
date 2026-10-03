# Ensaio de uma automação em conversas reais da conta (#859).
#
# Responde "o que esta regra faria agora", sem fazer nada: as condições passam pelo
# mesmo `ConditionsFilterService` que o listener usa, e as ações só são LISTADAS.
# Nenhum `ActionService` é chamado, nenhuma linha é gravada.
#
# As conversas são as mais recentes que a pessoa enxerga (a mesma regra de caixa do
# painel). Do contato sai só o nome — o ensaio não precisa de e-mail nem telefone.
#
# Condição "mudou de valor" depende do evento que mudou o campo; numa conversa parada
# não há evento, então essa parte sai do ensaio e volta em `sem_teste`. Quando ela é a
# regra inteira, não sobra o que testar: `testavel` vem falso e nenhuma conversa é
# listada — rodar o filtro sem condição diria que a regra pega todas.
#
# Em "mensagem criada" o listener avalia a regra a cada mensagem que não ignora
# (AutomationRuleListener#ignore_message_created_event?): enviada, nota privada e
# mensagem automática do canal contam; atividade, resposta automática de e-mail e
# disparo de campanha, não. O ensaio faz o mesmo com as últimas dessas mensagens: a
# conversa é afetada se a regra pegaria alguma delas.
class AutomationRules::Ensaio
  class Invalida < StandardError; end

  MAX_CONVERSAS = 10
  MUDOU_DE_VALOR = 'attribute_changed'.freeze
  EVENTO_DE_MENSAGEM = 'message_created'.freeze
  # Mensagens recentes lidas por conversa, e quantas delas (das que o listener
  # consideraria) passam pelo filtro — uma consulta cada.
  MENSAGENS_LIDAS = 20
  MENSAGENS_ENSAIADAS = 5

  def initialize(rule:, user:, quantidade: nil)
    @rule = rule
    @account = rule.account
    @user = user
    @quantidade = (quantidade.presence || MAX_CONVERSAS).to_i.clamp(1, MAX_CONVERSAS)
  end

  def perform
    regra = regra_testavel
    raise Invalida, I18n.t('autonomia.automacoes.ensaio.condicoes_invalidas') unless condicoes_validas?(regra)

    testavel = Array(@rule.conditions).empty? || regra.conditions.any?
    resultados = testavel ? conversas.map { |conversa| ensaiar(regra, conversa) } : []
    { 'testavel' => testavel, 'resultados' => resultados, 'sem_teste' => partes_sem_teste }
  end

  private

  # Uma cópia que nunca vai ao banco: só as condições que dá para testar, e somente leitura
  # para que nenhum caminho do filtro consiga gravá-la.
  def regra_testavel
    regra = @rule.dup
    regra.conditions = condicoes_testaveis
    regra.readonly!
    regra
  end

  def condicoes_testaveis
    testaveis = Array(@rule.conditions).reject { |condicao| condicao['filter_operator'] == MUDOU_DE_VALOR }
    return testaveis if testaveis.empty?

    testaveis[0...-1] + [testaveis.last.merge('query_operator' => nil)]
  end

  def partes_sem_teste
    Array(@rule.conditions).select { |condicao| condicao['filter_operator'] == MUDOU_DE_VALOR }
                           .pluck('attribute_key')
  end

  # Conferido aqui, antes do filtro: o filtro marca a regra com erro de autorização
  # quando a condição é inválida, e o ensaio não pode mexer na regra de verdade.
  def condicoes_validas?(regra)
    AutomationRules::ConditionValidationService.new(regra).perform
  end

  def conversas
    visiveis = Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform
    visiveis.includes(:contact).order(last_activity_at: :desc).limit(@quantidade)
  end

  def ensaiar(regra, conversa)
    casou = casou?(regra, conversa)
    { 'conversation_id' => conversa.id, 'display_id' => conversa.display_id,
      'contato' => conversa.contact&.name.presence, 'casou' => casou,
      'faria' => casou ? acoes : [] }
  end

  def casou?(regra, conversa)
    return filtro_casa?(regra, conversa, {}) unless @rule.event_name == EVENTO_DE_MENSAGEM

    mensagens_consideradas(conversa).any? { |mensagem| filtro_casa?(regra, conversa, { message: mensagem }) }
  end

  def filtro_casa?(regra, conversa, opcoes)
    AutomationRules::ConditionsFilterService.new(regra, conversa, opcoes).perform == true
  end

  def mensagens_consideradas(conversa)
    conversa.messages.where.not(message_type: :activity).reorder(created_at: :desc).limit(MENSAGENS_LIDAS)
            .select { |mensagem| considerada_pelo_listener?(mensagem) }
            .first(MENSAGENS_ENSAIADAS)
  end

  def considerada_pelo_listener?(mensagem)
    !mensagem.auto_reply_email? && mensagem.additional_attributes.to_h['whatsapp_api_campaign_id'].blank?
  end

  def acoes
    Array(@rule.actions).pluck('action_name')
  end
end
