# O que a conversa precisa para mandar modelo de produto e carrossel (#1716, decisão do Rodrigo em 16/10/2026: "liberar
# para quem atende a caixa"): o catálogo de produtos, as fotos aprovadas do modelo e a foto do computador para um cartão.
# Vale para quem atende a CAIXA (membro ou administrador), só para aquela caixa: a mesma checagem da conversa
# (`InboxPolicy#show?`). Não abre a tela de Modelos nem criar ou alterar modelo (`WhatsappTemplatePolicy`, à parte).
class Whatsapp::Templates::ConversationAssetsPolicy < ApplicationPolicy
  def catalog?
    attends_inbox?
  end

  def products?
    attends_inbox?
  end

  def template?
    attends_inbox?
  end

  def media?
    attends_inbox?
  end

  private

  def attends_inbox?
    InboxPolicy.new(user_context, record).show?
  end
end
