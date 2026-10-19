# Reabrir a conversa como o "Reabrir" do painel (#1809): o mesmo que o Api::V1::Accounts::ConversationsController faz
# no toggle_status quando uma pessoa reabre (handle_human_open): status aberto, o robô sai do nome (ai_assignee) e o
# agente que reabriu fica com a conversa. Sem isso, "Não é spam" e "Restaurar" devolviam a conversa ao robô. O
# controller do Chatwoot não muda; quem reabre pelas pastas do e-mail chama aqui.
class ConversaCanal::ReabrirComoPessoa
  def initialize(conversation:, user:)
    @conversation = conversation
    @user = user
  end

  # Um save só: dentro da transação do MoverParaPasta, um segundo save apagaria a troca de status dos eventos do commit
  # (o conversation.status_changed e o conversation.opened sairiam sem ela).
  def perform
    @conversation.with_lock do
      @conversation.status = :open
      if @user.is_a?(User)
        @conversation.ai_assignee = nil
        @conversation.assignee = @user if @user.agent?
      end
      @conversation.save!
    end
  end
end
