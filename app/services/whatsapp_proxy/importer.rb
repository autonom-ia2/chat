# Grava as atribuições de proxy postas à mão antes do #1516 (arquivo JSON sem senha: session, webshare_id, host, port,
# city, engine), para o código reconhecer o IP já em uso e não trocá-lo. Idempotente. Cada stack importa só as linhas
# do seu motor (`engine` começa pelo nome do motor: "hubsegs (Hub2You)", "autonomia (Autonom.ia)").
# O HMAC da credencial atual sai da lista da Webshare: sem ele, a reconciliação reaplicaria (e reiniciaria) cada sessão.
class WhatsappProxy::Importer
  Result = Struct.new(:imported, :unchanged, :skipped, keyword_init: true)

  def initialize(entries:, engine:, client: Webshare::Client.new, output: $stdout)
    @entries = entries
    @engine = engine.to_s.strip
    @client = client
    @output = output
  end

  def perform
    raise ArgumentError, 'engine obrigatório (ex.: hubsegs ou autonomia)' if @engine.blank?

    proxies = @client.proxies
    result = Result.new(imported: 0, unchanged: 0, skipped: 0)
    selected.each { |entry| result[import(entry, proxies)] += 1 }
    result
  end

  private

  def selected
    @entries.select { |entry| entry['engine'].to_s.split.first == @engine }
  end

  def import(entry, proxies)
    session = entry['session'].to_s
    address = entry['host'].to_s
    port = entry['port'].to_i
    return skip(session, 'linha incompleta') if session.blank? || address.blank? || port <= 0

    taken_by = WhatsappProxy::Assignment.where(proxy_address: address).where.not(session_name: session).pick(:session_name)
    return skip(session, "IP #{address} já atribuído a #{taken_by}") if taken_by

    save(session, address, port, entry['webshare_id'].presence, proxies)
  end

  def save(session, address, port, webshare_id, proxies)
    # Pelo host: a linha sem webshare_id (proxy posto à mão) também é resolvida na lista.
    listed = proxies.find { |proxy| proxy.address == address }
    record = WhatsappProxy::Assignment.find_or_initialize_by(session_name: session)
    record.assign_attributes(
      proxy_address: address, proxy_port: port, webshare_proxy_id: listed&.id || webshare_id,
      credential_digest: listed&.credential_digest, assigned_at: record.assigned_at || Time.current
    )
    return report(:unchanged, session, record, listed) unless record.changed?

    record.save!
    report(:imported, session, record, listed)
  end

  def report(outcome, session, record, listed)
    @output.puts("[whatsapp_proxy][importar] #{outcome} session=#{session} server=#{record.server} (#{note(record, listed)})")
    outcome
  end

  def note(record, listed)
    return 'na lista da Webshare' if listed
    return 'fora da Webshare: reservado, o código não troca' if record.external?

    'fora da lista atual: a reconciliação vai trocar'
  end

  def skip(session, reason)
    @output.puts("[whatsapp_proxy][importar] skipped session=#{session}: #{reason}")
    :skipped
  end
end
