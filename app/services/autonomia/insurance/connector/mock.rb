# Connector de contrato: devolve exatamente o formato que o CLI `autonomia agger` devolve hoje
# (fixture sanitizada de 03/09/2026), sem tocar no AGGER. Senha "invalid" simula auth_required
# para o fluxo de erro ser testável de ponta a ponta na UI.
# Superclasse qualificada: na forma compacta o escopo léxico é o topo e `Base` seria o módulo global ::Base.
class Autonomia::Insurance::Connector::Mock < Autonomia::Insurance::Connector::Client
  include Leituras

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

  # O mock TEM que carregar os campos novos. Em 04/09/2026 ele foi escrito em snake_case enquanto o
  # adapter emitia camelCase, e a suíte inteira passou a validar a suposição contra ela mesma:
  # `session_expires_at` chegava nulo em produção e a sessão única nunca reusava nada. Mock que não
  # reflete o formato real é um teste que se aprova sozinho.
  #
  # Só a camada que ESTA chamada verifica fica `ok`. As outras seguem `unknown` — é o critério 1.2,
  # e o mock precisa ensinar a mesma regra que a produção segue.
  DIAGNOSTICO = {
    'evidence' => { 'check' => 'session_probe', 'outcome' => 'ok', 'detail' => 'GET /cfg/corretora' },
    'layers' => { 'runtime' => 'ok', 'platform_auth' => 'ok', 'insurer_auth' => 'unknown',
                  'product_support' => 'unknown', 'risk' => 'unknown' }
  }.freeze

  def connection_status(provider:, session:)
    require_session!(session)
    {
      'platform' => provider,
      'status' => 'ready',
      'account_label' => 'CORRETORA DE TESTE (mock)',
      'session_expires_at' => 3.hours.from_now.utc.iso8601,
      'checked_at' => Time.current.utc.iso8601,
      **DIAGNOSTICO
    }
  end

  def capabilities(provider:, session:)
    require_session!(session)
    { 'platform' => provider, 'scanned_at' => Time.current.utc.iso8601, 'products' => products }
  end

  # O CONTRATO DE RAMO, no mesmo formato que o adapter devolve — camelCase de lá já traduzido, como
  # `Connector::Http` faz na fronteira. Em 04/09/2026 o mock foi escrito em snake_case enquanto o
  # adapter emitia camelCase, e a suíte inteira passou a validar a suposição contra ela mesma.
  #
  # Só o essencial de dois ramos: o mock não é catálogo, é contrato. O que ele precisa ensinar é a
  # FORMA — `origem` separando o que se pergunta do que se busca, e `obrigatorio` dizendo o que o
  # ramo exige.
  # O SCHEMA DE AUTO É O DO ADAPTER, gerado — não digitado (entrega 2, termo 1). O arquivo ao lado
  # é a saída de `agger quote schema auto` da CLI do adapter, com as chaves no formato que o
  # `Http` entrega (`condicional_a`). Regenerar quando o adapter mudar:
  #   (no autonomia-adapters) npx tsx src/cli/main.ts agger quote schema auto
  # A spec `parametros_spec` compara este arquivo com o formulário montado; o contrato real
  # (`http_contrato_real_spec`) é quem o compara com o adapter vivo.
  SCHEMA_AUTO = JSON.parse(File.read(File.expand_path('mock/schema_auto.json', __dir__))).freeze

  SCHEMAS = {
    'auto' => SCHEMA_AUTO.slice('ramo', 'campos'),
    # O CAMINHO ONDE O VALOR É ESCRITO, e não o nome solto. O adapter lê os campos do ramo de
    # `entrada.configuracoes`, e o segurado de `entrada.segurado`. Enquanto o mock declarava `marca`,
    # ele aprovava uma entrada que o portal ignora e reprovava a que ele aceita.
    'bike' => {
      'ramo' => '711',
      'campos' => [
        { 'campo' => 'segurado.nome', 'tipo' => 'texto', 'origem' => 'cliente', 'obrigatorio' => true },
        { 'campo' => 'segurado.cpfCnpj', 'tipo' => 'texto', 'origem' => 'cliente', 'obrigatorio' => true },
        { 'campo' => 'configuracoes.marca', 'tipo' => 'texto', 'origem' => 'cliente', 'obrigatorio' => true, 'padrao' => '1' },
        { 'campo' => 'configuracoes.valorMercado', 'tipo' => 'numero', 'origem' => 'cliente', 'obrigatorio' => true },
        { 'campo' => 'configuracoes.numeroSerie', 'tipo' => 'texto', 'origem' => 'cliente', 'obrigatorio' => true },
        { 'campo' => 'configuracoes.assist24hs', 'tipo' => 'numero', 'origem' => 'escolha', 'obrigatorio' => false, 'padrao' => 1 }
      ]
    }
  }.freeze

  # SEM SESSÃO, igual ao adapter real. Se o mock exigisse sessão aqui, a suíte aprovaria um
  # consumidor que só funciona com conexão pronta — e o valor destas duas é responder antes disso.
  def quote_schema(provider:, product:)
    require_provider!(provider)
    schema = SCHEMAS[product.to_s]
    raise ::Autonomia::Insurance::Connector::Error.new(:not_implemented, "sem adapter para #{product}") if schema.nil?

    { 'platform' => provider, 'product' => product.to_s, **schema }
  end

  # Recusa o que o schema exige e não veio. Não imita a checagem de domínio do adapter real (a troca
  # de tabela entre `seguradoraAnteriorId` e `seguradoraCodes`): o mock ensina a FORMA da resposta, e
  # fingir que conhece os códigos do portal seria a mesma mentira que o snake_case de 04/09.
  def quote_validate(provider:, product:, input:)
    campos = quote_schema(provider: provider, product: product)['campos']
    # SÓ O QUE O CLIENTE INFORMA. `origem` separa o que se pergunta do que o adapter busca: nome e
    # nascimento são obrigatórios e o adapter os procura por CPF, e cobrá-los aqui mataria o caminho
    # que o produto promete — "CPF e placa". O adapter real filtra pela mesma regra.
    problemas = campos.select { |c| c['origem'] == 'cliente' }
                      .select { |c| exigido_agora?(c, input) && sem_valor?(input, c['campo']) }
                      .map do |c|
      { 'campo' => c['campo'], 'severidade' => 'erro',
        'motivo' => 'obrigatório para cotar este ramo, e não veio na entrada.' }
    end
    { 'valido' => problemas.empty?, 'problemas' => problemas, 'entrada' => Normalizacao.normalizada(campos, input) }
  end

  # A cotação do mock imita o que importa do portal: ela DEMORA e chega em pedaços. O id carrega o
  # instante da submissão, e é só com o relógio que o mock decide o que já respondeu — assim o
  # caminho assíncrono inteiro (aceite no turno, polling, entrega parcial, entrega final) é
  # testável de ponta a ponta sem uma linha de rede.
  PARTIAL_AFTER = 5.seconds
  COMPLETE_AFTER = 20.seconds

  # ACEITA OS RAMOS QUE O MOCK CONHECE, e não só auto.
  #
  # Até 08/09/2026 esta linha era `if product.to_s != 'auto'`, e ela mentia sobre o adapter real, que
  # cota onze ramos desde 07/09. Um consumidor novo dos outros dez não teria como ser exercitado
  # sem AGGER — e mock que não reflete o real é teste que se aprova sozinho, o mesmo defeito do
  # snake_case de 04/09.
  #
  # `placa` continua exigida SÓ em auto: é campo de veículo, e cobrá-la de uma bicicleta seria
  # inventar contrato que o portal não tem.
  def quote_start(provider:, session:, product:, input:)
    require_provider!(provider)
    require_session!(session)
    require_produto!(product)
    # `vehicle.plate`, e não `placa` no topo. A checagem olhava a chave errada desde que existe, e
    # nunca foi exercitada porque os exemplos da ferramenta de auto usavam dublê em vez do mock —
    # ela recusaria toda cotação de auto de quem usasse o mock de verdade.
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'placa ausente') if sem_placa?(product, input)

    quote_id = "mock-#{Time.current.to_i}:1"
    Leituras.entradas[quote_id] = input.to_h.deep_stringify_keys
    { 'quote_id' => quote_id, 'status' => 'queued' }
  end

  def quote_result(provider:, session:, quote_id:)
    require_provider!(provider)
    require_session!(session)
    elapsed = Time.current.to_i - quote_id.to_s.split(':').first.to_s.delete_prefix('mock-').to_i
    status, offers = mock_progress(elapsed)
    # SEM `product` FIXO. Ele dizia 'auto' para qualquer cotação — e um consumidor que confiasse
    # nesse campo leria "auto" numa cotação de bicicleta. O mock não sabe o produto a partir do id,
    # então não afirma o que não sabe.
    { 'quote_id' => quote_id, 'status' => status, 'offers' => offers }
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

  # Auto sem placa não cota: o portal precisa dela ou do código FIPE para saber qual é o veículo.
  def sem_placa?(product, input)
    product.to_s == 'auto' && input.to_h.dig('vehicle', 'plate').blank?
  end

  # Os produtos que o mock sabe cotar: os que têm contrato de ramo declarado, mais auto, cujo
  # contrato de entrada é o `AutoQuoteInput` do adapter e não passa por `SCHEMAS`.
  def require_produto!(product)
    return if SCHEMAS.key?(product.to_s) || product.to_s == 'auto'

    raise ::Autonomia::Insurance::Connector::Error.new(:not_implemented, "sem adapter para #{product}")
  end

  # Obrigatório sempre; ou condicional, e aí só quando o grupo de que depende veio. Espelha
  # `exigidoAgora` do adapter — sem isso o mock cobraria `driver.name` de quem não tem condutor.
  def exigido_agora?(campo, input)
    return true if campo['obrigatorio']
    return false if campo['condicional_a'].blank?

    !valor_em(input, campo['condicional_a']).nil?
  end

  # Nulo e vazio contam como ausente, igual ao adapter: para campo obrigatório não há o que mandar.
  def sem_valor?(input, caminho)
    valor = valor_em(input, caminho)
    valor.nil? || valor == ''
  end

  def valor_em(input, caminho)
    caminho.to_s.split('.').reduce(input) do |atual, parte|
      atual.is_a?(Hash) ? (atual[parte] || atual[parte.to_sym]) : nil
    end
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
