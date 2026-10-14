# Grava as atribuições de proxy postas à mão antes do #1516 (arquivo JSON sem senha: session, webshare_id, host, port,
# city, engine, plano), para o código reconhecer o IP já em uso. Idempotente. Cada stack importa só as linhas do seu
# motor (`engine` começa pelo nome do motor: "hubsegs (Hub2You)", "autonomia (Autonom.ia)"). A conta sai da sessão no
# banco; o plano do IP, do campo `plano`. Se o plano não bate com o tipo da sessão (ex.: Híbrido num IP de datacenter),
# a reconciliação troca depois, dentro do limite por rodada.
# O HMAC da credencial atual sai da lista da Webshare: sem ele, a reconciliação reaplicaria (e reiniciaria) cada sessão.
class WhatsappProxy::Importer
  Result = Struct.new(:imported, :unchanged, :skipped, keyword_init: true)

  def initialize(entries:, engine:, pools: {}, output: $stdout)
    @entries = entries
    @engine = engine.to_s.strip
    @pools = pools.transform_keys(&:to_s)
    @output = output
  end

  def perform
    raise ArgumentError, 'engine obrigatório (ex.: hubsegs ou autonomia)' if @engine.blank?

    result = Result.new(imported: 0, unchanged: 0, skipped: 0)
    selected.each { |entry| result[import(entry)] += 1 }
    result
  end

  private

  def selected
    @entries.select { |entry| entry['engine'].to_s.split.first == @engine }
  end

  def pool(name)
    @pools[name] ||= WhatsappProxy::Pool.new(name)
  end

  # "static_residential_isp" → isp; "proxy_server_datacenter…" → datacenter.
  def pool_name(plano)
    plano = plano.to_s
    return 'isp' if plano == 'static_residential_isp'

    'datacenter' if plano.start_with?('proxy_server_datacenter')
  end

  def import(entry)
    session = entry['session'].to_s
    address = entry['host'].to_s
    port = entry['port'].to_i
    pool_name = pool_name(entry['plano'])
    return skip(session, 'linha incompleta') if session.blank? || address.blank? || port <= 0
    return skip(session, "plano desconhecido: #{entry['plano']}") if pool_name.nil?

    owner = WhatsappProxy::SessionOwner.find(session)
    return skip(session, 'sessão sem caixa nesta stack') if owner.nil?

    save(session, owner, pool_name, address, port, entry['webshare_id'].presence)
  end

  def save(session, owner, pool_name, address, port, webshare_id) # rubocop:disable Metrics/ParameterLists
    # Pelo host: a linha sem webshare_id (proxy posto à mão) também é resolvida na lista.
    listed = pool(pool_name).proxies.find { |proxy| proxy.address == address }
    record = WhatsappProxy::Assignment.find_or_initialize_by(session_name: session)
    record.assign_attributes(
      account_id: owner.account_id, pool: pool_name, proxy_address: address, proxy_port: port,
      webshare_proxy_id: listed&.id || webshare_id, credential_digest: listed&.credential_digest,
      assigned_at: record.assigned_at || Time.current
    )
    return report(:unchanged, session, record, listed) unless record.changed?
    return skip(session, record.errors.full_messages.to_sentence) unless record.save

    report(:imported, session, record, listed)
  end

  def report(outcome, session, record, listed)
    @output.puts("[whatsapp_proxy][importar] #{outcome} session=#{session} conta=#{record.account_id} " \
                 "server=#{record.server} plano=#{record.pool} (#{note(record, listed)})")
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
