# Põe proxy numa sessão que já existe no motor e ainda não tem atribuição (#1516) — uma por vez, à mão
# (`autonomia:whatsapp_proxy:migrar[sessao]`). Abrir a aba ou reconectar nunca fazem isso sozinhos.
# - Pega a mesma trava do ApplyJob (WhatsappProxy::SessionLock); ocupada, recusa.
# - Confere o limite temporário do WhatsApp (/timelock): com restrição ativa, ou sem conseguir conferir, recusa.
# - A troca é a do SessionUpdater (espera WORKING com o mesmo número; falhou, volta). Qualquer fim que não seja a troca
#   aplicada — desfeita, recusada, exceção, Ctrl-C — apaga a atribuição, para nenhuma atribuição órfã ser aplicada
#   depois sem o /timelock. Volta que falhou: o motor é relido; só se ele estiver com o IP atribuído a atribuição fica
#   (igual ao motor) — senão, ou ilegível, também é apagada.
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

    keep = false
    begin
      proxy = @assigner.for(session_name)
      return Result.new(:refused, 'sem IP disponível (veja os alertas)') if proxy.nil?

      outcome = @updater.apply!(session_name, proxy)
      keep = outcome == :applied || (outcome == :rollback_failed && engine_on?(session_name, proxy))
      finish(session_name, proxy, outcome, keep)
    ensure
      @assigner.release!(session_name) unless keep
    end
  end

  # Depois de uma volta que falhou: o motor está com o IP atribuído? Grava o que ele mostra (credencial incluída).
  def engine_on?(session_name, proxy)
    server, digest = WhatsappProxy::EngineProxy.read(@client, session_name)
    return false unless WhatsappProxy::Server.same?(server, proxy.server)

    WhatsappProxy::Assignment.find_by(session_name: session_name)&.rollback_failed!(engine_server: server, engine_digest: digest)
    true
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

  def finish(session_name, proxy, outcome, kept)
    case outcome
    when :applied
      @assigner.mark_applied!(session_name, proxy)
      Result.new(:applied, proxy.server)
    when :rollback_failed
      Result.new(:rollback_failed, kept ? 'volta falhou; o motor ficou com o proxy novo (mantido)' : 'volta falhou; atribuição apagada')
    when :refused then Result.new(:refused, 'sessão pedindo QR ou parada')
    else Result.new(outcome, 'troca desfeita; a sessão voltou ao que era')
    end
  end
end
