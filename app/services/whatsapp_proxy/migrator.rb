# Põe proxy numa sessão que já existe no motor e ainda não tem atribuição (#1516) — uma por vez, à mão
# (`autonomia:whatsapp_proxy:migrar[sessao]`). Abrir a aba ou reconectar nunca fazem isso sozinhos.
# Antes confere o limite temporário do WhatsApp (/timelock): com restrição ativa (ou sem conseguir conferir), recusa.
# A troca é a do SessionUpdater (espera WORKING com o mesmo número; falhou, volta). Desfeita ou recusada: a atribuição
# é apagada e a sessão fica como estava.
class WhatsappProxy::Migrator
  Result = Struct.new(:outcome, :detail)

  def initialize(client: Waha::Client.new, assigner: WhatsappProxy::Assigner.new, updater: nil)
    @client = client
    @assigner = assigner
    @updater = updater || WhatsappProxy::SessionUpdater.new(client: client)
  end

  def call(session_name)
    refusal = precheck(session_name)
    return Result.new(:refused, refusal) if refusal

    proxy = @assigner.for(session_name)
    return Result.new(:refused, 'sem IP disponível (veja os alertas)') if proxy.nil?

    finish(session_name, proxy, @updater.apply!(session_name, proxy))
  end

  private

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
    if outcome == :applied
      @assigner.mark_applied!(session_name, proxy)
      return Result.new(:applied, proxy.server)
    end

    @assigner.release!(session_name)
    Result.new(outcome, outcome == :refused ? 'sessão pedindo QR ou parada' : 'troca desfeita; a sessão voltou ao que era')
  end
end
