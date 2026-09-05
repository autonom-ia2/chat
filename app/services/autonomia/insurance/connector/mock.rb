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
      'checked_at' => Time.current.utc.iso8601,
      # O mock TEM que carregar os campos novos. Em 04/09/2026 ele foi escrito em snake_case
      # enquanto o adapter emitia camelCase, e a suíte inteira passou a validar a suposição contra
      # ela mesma: `session_expires_at` chegava nulo em produção e a sessão única nunca reusava
      # nada. Mock que não reflete o formato real é um teste que se aprova sozinho.
      'evidence' => {
        'check' => 'session_probe',
        'at' => Time.current.utc.iso8601,
        'outcome' => 'ok',
        'detail' => 'GET /cfg/corretora'
      },
      # Só a camada que ESTA chamada verifica fica `ok`. As outras seguem `unknown` — é o critério
      # 1.2, e o mock precisa ensinar a mesma regra que a produção segue.
      'layers' => {
        'runtime' => 'ok',
        'platform_auth' => 'ok',
        'insurer_auth' => 'unknown',
        'product_support' => 'unknown',
        'risk' => 'unknown'
      }
    }
  end

  def capabilities(provider:, session:)
    require_session!(session)
    { 'platform' => provider, 'scanned_at' => Time.current.utc.iso8601, 'products' => products }
  end

  # A cotação do mock imita o que importa do portal: ela DEMORA e chega em pedaços. O id carrega o
  # instante da submissão, e é só com o relógio que o mock decide o que já respondeu — assim o
  # caminho assíncrono inteiro (aceite no turno, polling, entrega parcial, entrega final) é
  # testável de ponta a ponta sem uma linha de rede.
  PARTIAL_AFTER = 5.seconds
  COMPLETE_AFTER = 20.seconds

  def quote_start(provider:, session:, product:, input:)
    require_provider!(provider)
    require_session!(session)
    raise ::Autonomia::Insurance::Connector::Error.new(:not_implemented, "sem adapter para #{product}") if product.to_s != 'auto'
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'placa ausente') if input.to_h['placa'].blank?

    { 'quote_id' => "mock-#{Time.current.to_i}:1", 'status' => 'queued' }
  end

  def quote_result(provider:, session:, quote_id:)
    require_provider!(provider)
    require_session!(session)
    elapsed = Time.current.to_i - quote_id.to_s.split(':').first.to_s.delete_prefix('mock-').to_i
    status, offers = mock_progress(elapsed)
    { 'quote_id' => quote_id, 'product' => 'auto', 'status' => status, 'offers' => offers }
  end

  def quote_proposal(provider:, session:, quote_id:, insurer_code: nil)
    require_provider!(provider)
    require_session!(session)
    nome = insurer_code.present? ? "proposta-#{insurer_code}" : 'comparativo'
    { 'quote_id' => quote_id, 'url' => "https://exemplo.test/#{nome}-mock.pdf" }
  end

  private

  # Duas seguradoras respondem cedo, a terceira demora. É o formato que a entrega parcial existe
  # para atender: mandar as duas primeiras em vez de segurar tudo pela mais lenta.
  def mock_progress(elapsed)
    return ['running', []] if elapsed < PARTIAL_AFTER
    return ['partial', [offer('8', 'Porto Seguro', 1200.5), offer('3', 'Mapfre', 1340.0)]] if elapsed < COMPLETE_AFTER

    ['completed', [offer('8', 'Porto Seguro', 1200.5), offer('3', 'Mapfre', 1340.0), offer('47', 'Justos', 1098.9)]]
  end

  def offer(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name, 'enabled' => true, 'integrationStatus' => 'ready' },
      'status' => 'quoted', 'premium' => { 'amount' => amount, 'currency' => 'BRL' } }
  end

  # O serviço real devolve 404 para plataforma desconhecida; o mock recusa pelo mesmo motivo — só
  # sabe falar AGGER, e fingir que sabe outra coisa esconderia um erro de configuração.
  def require_provider!(provider)
    return if ::Autonomia::Insurance::Connection::PROVIDERS.include?(provider.to_s)

    raise ::Autonomia::Insurance::Connector::Error.new(:not_implemented, "sem adapter para #{provider}")
  end

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
