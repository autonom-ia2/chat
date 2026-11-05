# #2414 F9 P7 (#2568): a mudança que uma Automação livre faz na conversa aparece como dela, com quem a ligou:
# "Atribuído a Maria por Automação «Boas-vindas» · ligada por Juliana". A automação age pela porta da frente
# (Autonomia::Guide::ChamadaInterna) como quem a ligou. Sem isto, a atividade dizia "por Juliana", e a atribuição para
# a própria Juliana virava "Juliana atribuiu a si mesma" e não a avisava.
#
# Quem age vem da cadeia (Autonomia::Automacao::Cadeia.automacao_livre), não do `Current`: o pedido de dentro mexe no
# `Current`, a cadeia sobrevive a ele. Fora de uma Automação livre (pessoa, regra antiga, automação de etapa), tudo
# segue como antes.
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

  def automacao_livre_que_age
    id = Autonomia::Automacao::Cadeia.automacao_livre&.dig(:id)
    automacao = id && Autonomia::Automacao::Definicao.includes(:ligada_por).find_by(id: id, account_id: account_id)
    return unless automacao

    quem_ligou = automacao.ligada_por&.name
    return I18n.t('automation.livre.sem_quem_ligou', nome: automacao.nome) if quem_ligou.blank?

    I18n.t('automation.livre.com_quem_ligou', nome: automacao.nome, user_name: quem_ligou)
  end
end
