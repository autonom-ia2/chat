# Quem falou e a que horas, na linha que a IA de assunto lê (IA entende a conversa F1, Autonomia::Decisores::Estado com
# `papeis: true`): "[HH:MM] Customer", "[HH:MM] Our assistant (AI)"... A hora sai no fuso da conversa (o do contato,
# senão o da conta, como nos follow-ups). A mensagem recebida mantém o autor que o Estado já dava (o cliente, ou quem
# escreveu de outro endereço no e-mail, #1807).
class Crm::Ai::FatosDaConversa::Rotulo
  def initialize(conversation)
    @conversation = conversation
  end

  def de(mensagem, autor_recebido)
    quem = mensagem.incoming? ? autor_recebido : Crm::Ai::FatosDaConversa::ROTULOS.fetch(papel(mensagem))
    "[#{mensagem.created_at.in_time_zone(fuso).strftime('%H:%M')}] #{quem}"
  end

  private

  def papel(mensagem)
    @robos ||= Crm::Ai::PapelDaMensagem.robos_da_conta(mensagem.account_id)
    Crm::Ai::PapelDaMensagem.de(mensagem, robos: @robos)
  end

  def fuso
    @fuso ||= Crm::Ai::Config.resolved_timezone(account: @conversation&.account, contact: @conversation&.contact)
  end
end
