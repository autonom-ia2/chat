# A CARTEIRA DO MOCK (E7, #2900): as quatro operações da carteira da corretora, com dados FICTÍCIOS e coerentes, no
# formato que o `Http` entrega (snake_case). Nenhum nome, documento ou número aqui é de gente ou de seguradora de verdade.
#
# O que o mock ensina, porque a tela e a sincronização precisam lidar com tudo isso:
# - o pedido às vezes devolve avisos (`por_seguradora`), como o adapter faz com a evidência do cadastro de logins: no
#   período de mais de um mês (a primeira busca), uma seguradora com o login recusado (`pede_login`) e uma, sem nome, em
#   que a corretora não guardou o login (`sem_login`); no período curto (a de todo dia), a lista vem vazia (cadastro lido,
#   nada a avisar);
# - o robô DEMORA: o `sync_id` carrega o instante do pedido, e o andamento fica `buscando` por `BUSCANDO_POR` (só a
#   busca pedida antes de 15/11/2026 ainda pergunta);
# - a lista vem em duas páginas, com um item sem `ref` (não dá para trazer), um endosso da mesma apólice (mesmo `ref`)
#   e um registro que o adapter não leu (`ignorados`). `total` é itens + ignorados, como no adapter;
# - o documento devolve um endereço que não existe fora do teste: baixar falha, e a falha não pode travar o lote;
# - as datas NÃO andam com o relógio a cada dia (`base`): o mesmo registro buscado amanhã é o mesmo seguro, com as mesmas
#   datas, como no Agger. Se andassem, a busca de todo dia traria um "termo novo" de cada seguro por dia
#   (Carteira::Termo), e o seguro nasceria de novo. Elas partem do começo do mês e só mudam na virada dele; o seguro
#   termina 40 dias depois desse começo, então ainda vale em qualquer dia do mês.
module Autonomia::Insurance::Connector::Mock::CarteiraDaCorretora
  BUSCANDO_POR = 5.seconds
  # O período mais longo que o adapter aceita.
  MESES_NO_MAXIMO = 37
  PREFIXO = 'mock-carteira'.freeze
  SEGUNDA_PAGINA = 'mock-pagina-2'.freeze
  SEGURADORAS = [
    { 'codigo' => '901', 'nome' => 'Seguradora Azul (exemplo)' },
    { 'codigo' => '902', 'nome' => 'Seguradora Verde (exemplo)' }
  ].freeze
  AVISOS = [
    { 'codigo' => '903', 'nome' => 'Seguradora Sol (exemplo)', 'situacao' => 'pede_login' },
    { 'codigo' => '904', 'nome' => nil, 'situacao' => 'sem_login' }
  ].freeze
  IGNORADOS = 1

  def portfolio_sync_start(provider:, session:, desde:, ate:)
    require_provider!(provider)
    require_session!(session)
    datas = [desde, ate].map { |data| Date.iso8601(data.to_s) }
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'periodo fora do formato') if datas.first > datas.last
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'periodo longo demais') if datas.first < datas.last - MESES_NO_MAXIMO.months

    avisos = datas.first < datas.last - 1.month ? AVISOS.map(&:dup) : []
    { 'sync_id' => "#{PREFIXO}:#{Time.current.to_i}", 'status' => 'buscando', 'por_seguradora' => avisos }
  rescue Date::Error
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'periodo fora do formato')
  end

  def portfolio_sync_status(provider:, session:, sync_id:)
    require_provider!(provider)
    require_session!(session)
    situacao = segundos_do_pedido(sync_id) < BUSCANDO_POR.to_i ? 'buscando' : 'pronta'
    { 'status' => situacao, 'por_seguradora' => SEGURADORAS.map { |seguradora| seguradora.merge('situacao' => situacao) } }
  end

  def portfolio_policies(provider:, session:, sync_id:, cursor: nil)
    require_provider!(provider)
    require_session!(session)
    exigir_sync!(sync_id)
    pagina = cursor.to_s == SEGUNDA_PAGINA ? 2 : 1
    { 'itens' => pagina == 1 ? primeira_pagina : segunda_pagina, 'proximo_cursor' => pagina == 1 ? SEGUNDA_PAGINA : nil,
      'total' => primeira_pagina.size + segunda_pagina.size + IGNORADOS, 'ignorados' => pagina == 2 ? IGNORADOS : 0 }
  end

  def portfolio_document(provider:, session:, ref:)
    require_provider!(provider)
    require_session!(session)
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'ref fora do formato') if ref.blank?

    { 'url' => 'https://exemplo.test/apolice-mock.pdf' }
  end

  private

  def segundos_do_pedido(sync_id)
    exigir_sync!(sync_id)
    Time.current.to_i - sync_id.to_s.split(':')[1].to_i
  end

  def exigir_sync!(sync_id)
    return if sync_id.to_s.start_with?("#{PREFIXO}:")

    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'sync_id fora do formato')
  end

  def primeira_pagina
    [
      apolice('mock-ref-1', '1001', 'Seguradora Azul (exemplo)', 'Automóvel',
              segurado('Pessoa Exemplo Um', '10020030088', 'pessoa.um@exemplo.test'), item: 'Carro de exemplo'),
      apolice('mock-ref-2', '1002', 'Seguradora Verde (exemplo)', 'Residencial',
              segurado('Pessoa Exemplo Dois', '40050060007', nil), item: 'Apartamento de exemplo'),
      apolice(nil, '1003', 'Seguradora Azul (exemplo)', 'Vida', segurado('Pessoa Exemplo Tres', '70080090036', nil))
    ]
  end

  # O endosso da apólice da primeira página (o mesmo `ref`) mudou o valor.
  def segunda_pagina
    endosso = { 'numero' => '1', 'data' => base.prev_month.iso8601 }
    [
      apolice('mock-ref-1', '1001', 'Seguradora Azul (exemplo)', 'Automóvel',
              segurado('Pessoa Exemplo Um', '10020030088', 'pessoa.um@exemplo.test'),
              item: 'Carro de exemplo', endosso: endosso, premio: 260_000),
      apolice('mock-ref-4', '1004', 'Seguradora Verde (exemplo)', 'Empresarial',
              segurado('Pessoa Exemplo Quatro', '11122233396', nil), item: 'Loja de exemplo')
    ]
  end

  def base
    Date.current.beginning_of_month
  end

  def segurado(nome, documento, email)
    { 'nome' => nome, 'documento' => documento, 'email' => email }
  end

  # rubocop:disable Metrics/ParameterLists -- um item fictício inteiro, com o que muda de um para o outro
  def apolice(ref, numero, seguradora, ramo, segurado, item: nil, endosso: nil, premio: 240_000)
    # rubocop:enable Metrics/ParameterLists
    inicio = base.prev_year + 40
    { 'ref' => ref, 'numero' => numero, 'seguradora' => seguradora, 'ramo' => ramo, 'inicio_vigencia' => inicio.iso8601,
      'fim_vigencia' => (inicio + 1.year).iso8601, 'emissao' => (inicio - 5).iso8601, 'premio_centavos' => premio,
      'segurado' => segurado, 'item' => item, 'endosso' => endosso, 'parcelas' => nil, 'pdf_ref' => ref && "mock-pdf-#{ref}" }
  end
end
