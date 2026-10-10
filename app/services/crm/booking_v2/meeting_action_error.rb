# Recusa de uma ação do agente no dia da reunião (#1193): "Lembrar" e "Enviar link para marcar outro horário". É um
# ArgumentError com o código como mensagem; o controller responde 422 `crm.booking_v2.<código>` só para esta classe.
# `url`: o link do cliente, quando a mensagem não pôde sair mas o agente pode copiá-lo e mandar por conta própria.
class Crm::BookingV2::MeetingActionError < ArgumentError
  attr_reader :url

  def initialize(code, url: nil)
    super(code)
    @url = url
  end
end
