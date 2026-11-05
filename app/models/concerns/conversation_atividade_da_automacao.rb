# #2414 F9 P7 (#2568): a mudança que uma Automação livre faz na conversa aparece como dela, com quem a ligou:
# "Atribuído a Maria por Automação «Boas-vindas» · ligada por Juliana". A automação age pela porta da frente
# (Autonomia::Guide::ChamadaInterna) como quem a ligou. Sem isto, a atividade dizia "por Juliana", e a atribuição para
# a própria Juliana virava "Juliana atribuiu a si mesma" e não a avisava.
#
# Quem age vem do ato (Autonomia::Automacao::Ato), aberto só em volta do pedido que a automação faz. Não vem da cadeia:
# ela viaja no evento, e quem age depois (Atribuição, agente de IA) a herda sem ter sido a automação. Fora desse
# pedido (pessoa, regra antiga, automação de etapa, listener do evento), tudo segue como antes.
module ConversationAtividadeDaAutomacao
  extend ActiveSupport::Concern

  private

  # Status, prioridade, etiqueta e SLA.
  def determine_user_name
    automacao_livre_que_age || super
  end

  # Atribuição e equipe (que leem o `Current.user` direto), etiqueta e SLA.
  def activity_message_owner(user_name)
    automacao_livre_que_age || super
  end

  # Quem ligou a automação não se atribuiu: a automação atribuiu. Vale para o texto e para o aviso de atribuição.
  def self_assign?(assignee_id)
    return false if automacao_livre_que_age

    super
  end

  # Um save chama isto várias vezes (texto, atribuição, aviso): uma consulta por automação, guardada na conversa.
  def automacao_livre_que_age
    id = Autonomia::Automacao::Ato.automacao_id
    return unless id

    @automacao_livre_que_age ||= {}
    return @automacao_livre_que_age[id] if @automacao_livre_que_age.key?(id)

    @automacao_livre_que_age[id] = texto_da_automacao(id)
  end

  def texto_da_automacao(id)
    automacao = Autonomia::Automacao::Definicao.where(id: id, account_id: account_id).left_joins(:ligada_por)
    nome, quem_ligou = automacao.pick(:nome, 'users.name')
    return unless nome
    return I18n.t('automation.livre.sem_quem_ligou', nome: nome) if quem_ligou.blank?

    I18n.t('automation.livre.com_quem_ligou', nome: nome, user_name: quem_ligou)
  end
end
