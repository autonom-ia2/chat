# #2216 — Prepend em Api::V1::Accounts::ConversationsController (config/initializers/reabrir_ao_escrever.rb).
# Começar conversa numa caixa com "Reabrir a mesma conversa" (lock_to_single_conversation) cai na última conversa do
# contato, mesmo resolvida ou adiada (ConversationBuilder#look_up_exising_conversation). A mensagem do atendente não
# reabre (Message#reopen_conversation só olha a do cliente), e a conversa ficava fora das Abertas.
# Aqui, com o pedido da gaveta (Conversations::PedidoDeReabrir: sinal, pessoa com sessão do painel, mensagem que não é
# nota privada), a conversa achada reabre antes de a mensagem entrar, sem mudar quem cuida (#2067: atendente
# responde, não assume): nem o atendente que escreveu, nem o rodízio da caixa. Só se a pessoa pode operar a conversa
# (ConversationPolicy#show?, o mesmo do "Reabrir" do painel): a conversa oculta do #1505 entra a mensagem, mas não reabre.
# O ConversationBuilder fica igual: o widget, a API pública, as campanhas e os avisos de agendamento também passam por
# ele. A conversa visível vai pela API de mensagem (Conversations::ReabrirAoEscreverNaMensagem).
# Na mesma transação da criação: se a mensagem não sai, a conversa não reabre. A transação fecha dentro do `create`,
# antes da resposta, como no original: o número da conversa (display_id) só é lido depois do commit.
module Conversations::ReabrirAoEscrever
  include Conversations::PedidoDeReabrir

  def create
    ActiveRecord::Base.transaction do
      reabrir_conversa_achada
      super
    end
  end

  private

  # A mesma regra do ConversationBuilder#look_up_exising_conversation: com a caixa em "Reabrir a mesma conversa", a
  # última do contato (Conversation#reabrir_ao_escrever! confere a caixa e, sob a trava, a situação).
  def reabrir_conversa_achada
    mensagem = params[:message]
    return if mensagem.blank?
    return unless pedido_de_reabrir?(privada: ActiveModel::Type::Boolean.new.cast(mensagem[:private]))

    conversa = @contact_inbox.conversations.last
    return if conversa.blank? || !policy(conversa).show?

    conversa.reabrir_ao_escrever!
  end
end
