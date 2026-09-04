# Connector de contrato: devolve exatamente o formato que o CLI `autonomia agger` devolve hoje
# (fixture sanitizada de 03/09/2026), sem tocar no AGGER. Senha "invalid" simula auth_required
# para o fluxo de erro ser testável de ponta a ponta na UI.
# Superclasse qualificada: na forma compacta o escopo léxico é o topo e `Base` seria o módulo global ::Base.
class Autonomia::Insurance::Connector::Mock < Autonomia::Insurance::Connector::Client
  # Única operação que consome credencial, igual ao adapter real.
  def open_session(provider:, username:, password:)
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'credentials missing') if username.blank? || password.blank?
    raise ::Autonomia::Insurance::Connector::Error.new(:auth_required, 'invalid credentials') if password == 'invalid'

    {
      'platform' => provider,
      'data' => { 'aggregatorToken' => 'mock-aggregator-token', 'multicalculoToken' => 'mock-multicalculo-token' },
      'expires_at' => 3.hours.from_now.utc.iso8601,
      'account_label' => 'CORRETORA DE TESTE (mock)',
      'dropped_previous_session' => false
    }
  end

  def connection_status(provider:, session:)
    require_session!(session)
    {
      'platform' => provider,
      'status' => 'ready',
      'account_label' => 'CORRETORA DE TESTE (mock)',
      'session_expires_at' => 3.hours.from_now.utc.iso8601,
      'checked_at' => Time.current.utc.iso8601
    }
  end

  def capabilities(provider:, session:)
    require_session!(session)
    { 'platform' => provider, 'scanned_at' => Time.current.utc.iso8601, 'products' => products }
  end

  private

  # Espelha o adapter real: operação sem sessão é recusada em vez de abrir uma por conta própria.
  def require_session!(session)
    return if session.is_a?(Hash) && session.present?

    raise ::Autonomia::Insurance::Connector::Error.new(:auth_required, 'session missing')
  end

  def products
    [
      product('auto', '31', 'confirmed', %w[Prata Ouro Diamante],
              [ins('47', 'Justos', 10), ins('8', 'Porto Seguro', nil), ins('3', 'Mapfre', nil),
               ins('13', 'Mitsui', nil, 'auth_required')]),
      product('residencial', '2', 'inferred', %w[Prata], [ins('8', 'Porto Seguro', nil), ins('11', 'Tokio', nil)]),
      product('vida', '91', 'inferred', %w[Prata], [ins('25', 'Icatu', nil)])
    ]
  end

  def product(slug, ref, confidence, packages, insurers)
    { 'product' => slug, 'platformRef' => ref, 'labelConfidence' => confidence,
      'enabled' => insurers.any? { |i| i['enabled'] }, 'coveragePackages' => packages, 'insurers' => insurers }
  end

  def ins(code, name, commission, status = 'ready')
    { 'code' => code, 'name' => name, 'enabled' => status == 'ready', 'integrationStatus' => status,
      'defaultCommissionPercent' => commission }
  end
end
