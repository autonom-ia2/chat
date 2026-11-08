# IP da Webshare do número (#1516) durante a criação da caixa (#2478). Guarda a reserva de antes de pedir o IP: o
# desfazer volta a ela quando a sessão continua no motor (sessão reaproveitada, ou nada remoto feito) e só solta a
# reserva quando a sessão saiu do motor ou não havia reserva antes.
class Waha::InboxProvisioner::ProxyReservation
  attr_reader :proxy

  def initialize(assigner, session)
    @assigner = assigner
    @session = session
  end

  def take
    @before = WhatsappProxy::Assignment.find_by(session_name: @session)&.attributes&.except('id', 'created_at', 'updated_at')
    @taken = true
    @proxy = @assigner.for(@session)
  end

  def confirm!
    @proxy ? @assigner.mark_applied!(@session, @proxy) : @assigner.mark_pending!(@session)
  end

  # Volta à reserva de antes, sob a mesma trava e as mesmas validações do Assigner: se outra conta pegou o IP antigo
  # nesse meio-tempo, a volta não acontece (o número fica com o IP novo) e o log diz por quê.
  def undo!(session_removed:)
    return unless @taken
    return @assigner.release!(@session) if session_removed || @before.nil?

    WhatsappProxy::Assignment.exclusively do
      record = WhatsappProxy::Assignment.find_or_initialize_by(session_name: @session)
      record.assign_attributes(@before)
      record.save!
    end
  rescue StandardError => e
    Rails.logger.error("[Waha] proxy undo skipped session=***#{@session.last(4)}: #{e.class}")
  end
end
