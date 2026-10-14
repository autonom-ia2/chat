# Põe proxy numa sessão que já existe no motor e ainda não tem atribuição (#1516) — uma por vez, à mão
# (`autonomia:whatsapp_proxy:migrar[sessao]`). Abrir a aba ou reconectar nunca fazem isso sozinhos.
# - Pega a mesma trava do ApplyJob (WhatsappProxy::SessionLock); ocupada, recusa.
# - Confere o limite temporário do WhatsApp (/timelock): com restrição ativa, ou sem conseguir conferir, recusa.
# - A troca é a do SessionUpdater (espera WORKING com o mesmo número; falhou, volta). Qualquer fim que não seja a troca
#   aplicada — desfeita, recusada, exceção, Ctrl-C — apaga a atribuição, para nenhuma atribuição órfã ser aplicada
#   depois sem o /timelock. Exceção: volta que falhou (o motor ficou com o proxy novo) — aí a tabela fica igual ao motor.
class WhatsappProxy::Migrator
  Result = Struct.new(:outcome, :detail)

  def initialize(client: Waha::Client.new, assigner: WhatsappProxy::Assigner.new, updater: nil)
    @client = client
    @assigner = assigner
    @updater = updater || WhatsappProxy::SessionUpdater.new(client: client)
  end

  def call(session_name)
    result = WhatsappProxy::SessionLock.with(session_name) { migrate(session_name) }
    result == :locked ? Result.new(:refused, 'outra troca de proxy desta sessão está em andamento') : result
  end

  private

  def migrate(session_name)
    refusal = precheck(session_name)
    return Result.new(:refused, refusal) if refusal

    outcome = nil
    begin
      proxy = @assigner.for(session_name)
      return Result.new(:refused, 'sem IP disponível (veja os alertas)') if proxy.nil?

      outcome = @updater.apply!(session_name, proxy)
      finish(session_name, proxy, outcome)
    ensure
      @assigner.release!(session_name) unless %i[applied rollback_failed].include?(outcome)
    end
  end

  def precheck(session_name)
    return 'recurso desligado (WHATSAPP_PROXY_ENABLED) ou sem WEBSHARE_API_KEY' unless @assigner.enabled?
    return 'sessão já tem atribuição' if WhatsappProxy::Assignment.exists?(session_name: session_name)
    return 'sessão sem caixa nesta stack' if WhatsappProxy::SessionOwner.find(session_name).nil?

    timelock_refusal(session_name)
  end

  def timelock_refusal(session_name)
    timelock = @client.timelock(session_name)
    'o WhatsApp está restringindo conversas novas deste número agora (/timelock)' if timelock['isActive']
  rescue Waha::Client::Error => e
    "não deu para conferir o /timelock (#{e.class})"
  end

  def finish(session_name, proxy, outcome)
    case outcome
    when :applied
      @assigner.mark_applied!(session_name, proxy)
      Result.new(:applied, proxy.server)
    when :rollback_failed
      WhatsappProxy::Assignment.find_by(session_name: session_name)&.rollback_failed!(proxy.credential_digest)
      Result.new(:rollback_failed, 'a volta falhou: o motor ficou com o proxy novo (veja o alerta volta_falhou)')
    when :refused then Result.new(:refused, 'sessão pedindo QR ou parada')
    else Result.new(outcome, 'troca desfeita; a sessão voltou ao que era')
    end
  end
end
