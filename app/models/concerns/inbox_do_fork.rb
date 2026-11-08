# O que o fork pendura na caixa e precisa sair pela app quando ela é apagada (destroy síncrono, antes do DELETE).
# Incluído no mesmo ponto do Inbox em que as associações ficavam: a ordem dos callbacks de destroy não muda.
module InboxDoFork
  extend ActiveSupport::Concern

  included do
    # Conserto "caixa deletada" (Autonomia Agents): a FK autonomia_agent_inboxes.inbox_id (sem
    # ON DELETE CASCADE) barrava o Inbox#destroy quando havia agente conectado. dependent: :destroy
    # (síncrono, NÃO _async) remove o vínculo ANTES da deleção do Inbox → some a FK; e o
    # after_destroy de cada AgentInbox limpa o AgentBot-espelho + AgentBotInbox. Agente vira "sem caixa".
    # Inerte em instalações sem o módulo (tabela ausente ⇒ nenhuma linha associada).
    has_many :autonomia_agent_inboxes, class_name: 'Autonomia::Agents::AgentInbox', dependent: :destroy
    # #2487: o cuidado dos comentários sai pela app (não pela cascata do banco), para levar o material só do post junto
    # com os trechos e o arquivo.
    has_many :crm_meta_ads_comment_cares, class_name: 'Crm::MetaAdsCommentCare', dependent: :destroy
  end
end
