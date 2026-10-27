# Monta o painel de UM período do contrato v2 (#2251, épico #2226) a partir das procuras lidas. É o porte do
# `Agregador` do protótipo (bin/contrato.py, fora do repositório): mesmas regras, mesma ordem e mesmos arredondamentos,
# para a conta de referência ver os números aprovados. O teste-ouro local compara campo a campo.
# Por isso cada método espelha um do protótipo, e os que passam dos limites de tamanho do RuboCop ficam assim, com o
# aviso desligado no próprio método: partir só para o RuboCop afastaria o porte do original que o teste confere.
#
# Regra única: todo agregado sai da lista de procuras do período (sem as de teste). O que não é das procuras chega
# pronto em `fixos`:
# - `mensagens`: ->(inicio, fim) { [mensagens, tempo_de_resposta] } do período, ao vivo das mensagens da conta;
# - `equipe_por_mes`, `ticket`, `confianca`, `por_que` ({[conversa, procura] => texto}) e `exemplos`
#   ({'regras' => {id => [[conversa, procura]]}, ...}), as conversas que a leitura escolheu como exemplo;
# - `recomendacoes`: ->(chave, inicio, fim) { cartões | [] }, do cache;
# - `gerado_em`, `anuncios_ligados`, `origem_nota`.
# O catálogo (nomes) e a configuração (regra das contas) vêm da ficha do agente. Nada de nome de ramo no código.
class Autonomia::Desempenho::Agregador
  include Autonomia::Desempenho::Agregador::Base
  include Autonomia::Desempenho::Agregador::Topo
  include Autonomia::Desempenho::Agregador::Funil
  include Autonomia::Desempenho::Agregador::Recortes
  include Autonomia::Desempenho::Agregador::Qualidade
  include Autonomia::Desempenho::Agregador::Conversas

  POUCO_DADO = 20
  # O que, na vida real, é do histórico e não do período: a conferência (feita uma vez) e o valor típico da venda.
  SECOES_FIXAS = %w[confianca ticket].freeze

  attr_reader :cfg, :cat, :todas, :fixos, :inicio_dos_dados, :fim_dos_dados

  def initialize(configuracao:, catalogo:, procuras:, fixos:, inicio_dos_dados:, fim_dos_dados:) # rubocop:disable Metrics/ParameterLists
    @cfg = configuracao
    @cat = catalogo
    @todas = procuras.sort_by { |p| [p['inicio'], p['conversa'].to_i, p['procura']] }
    @fixos = fixos
    @compra_ids = Array(cfg['compra_pedidos']).to_set
    @duvida_ids = Array(cfg['duvida_pedidos']).to_set
    horario = cfg.dig('meta', 'horario_comercial') || {}
    @dias_uteis = Array(horario['dias_semana']).to_set
    @hora_ini = horario['inicio_hora']
    @hora_fim = horario['fim_hora']
    @inicio_dos_dados = inicio_dos_dados
    @fim_dos_dados = fim_dos_dados
  end

  # `anterior`: [inicio, fim] do período anterior, ou nil. `dados_ate`: 'AAAA-MM-DDTHH:MM' no fuso da conta.
  def painel(chave, inicio, fim, anterior:, dados_ate:, fonte:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
    ps = reais(inicio, fim)
    n = numeros(ps)
    ant = anterior ? numeros(reais(*anterior)) : nil
    msgs, tempo = fixos[:mensagens].call(inicio, fim)
    tempo_ant = anterior ? fixos[:mensagens].call(*anterior).last : nil
    funil = funil(n['compra'])
    qualidade = qualidade(ps, tempo, msgs)
    {
      'versao' => 2,
      'meta' => meta(chave, inicio, fim, anterior, dados_ate, fonte, ps, n, msgs),
      'kpis' => kpis(n, ant, tempo, tempo_ant),
      'evolucao' => evolucao(ps, inicio, fim, %w[7 30].include?(chave) ? 'dia' : 'semana', dados_ate),
      'funil' => funil,
      'indicadores' => indicadores(n, funil),
      'comparacoes' => comparacoes(n['compra']),
      'temas' => temas(ps, ant&.fetch('procuras')),
      'cortes' => cortes(ps, n['compra']),
      'origem' => origem(ps),
      'horarios' => horarios(ps),
      'qualidade' => qualidade,
      'pessoa' => pessoa(n),
      'quem' => quem(n),
      'conversas_ativas' => conversas_ativas(ps),
      'perdas' => perdas(n),
      'motivos' => motivos(ps),
      'ticket' => fixos[:ticket],
      'recomendacoes' => fixos[:recomendacoes].call(chave, inicio, fim),
      'confianca' => fixos[:confianca],
      'avisos' => avisos(chave, fim, dados_ate, ps)
    }
  end

  private

  def meta(chave, inicio, fim, anterior, dados_ate, fonte, lista, nums, msgs) # rubocop:disable Metrics/ParameterLists
    m = cfg['meta'] || {}
    {
      'fonte' => fonte, 'situacao' => nil, 'agente' => m['agente'], 'conta' => m['conta'],
      'periodo' => periodo(chave, inicio, fim, anterior),
      'dados_ate' => dados_ate, 'gerado_em' => fixos[:gerado_em], 'fuso' => m['fuso'],
      'horario_comercial' => m['horario_comercial'], 'nomes' => m['nomes'], 'definicoes' => m['definicoes'],
      'anuncios_ligados' => anuncios_ligados?, 'instrucao' => nil,
      'visibilidade' => { 'escopo' => 'conta', 'minimo' => 5 },
      'base' => { 'procuras' => lista.size, 'procuras_teste' => testes_no_periodo(inicio, fim), 'conversas' => nums['conversas'].size,
                  'mensagens' => msgs.slice('contato', 'agente', 'equipe', 'notas') }
    }
  end

  def periodo(chave, inicio, fim, anterior)
    {
      'chave' => chave, 'inicio' => inicio.iso8601, 'fim' => fim.iso8601, 'dias' => (fim - inicio).to_i + 1,
      'anterior' => anterior && { 'inicio' => anterior.first.iso8601, 'fim' => anterior.last.iso8601 }
    }
  end

  def testes_no_periodo(inicio, fim)
    ini = inicio.iso8601
    fi = fim.iso8601
    todas.count { |p| p['teste'] && Autonomia::Desempenho::Conta.dia_de(p['inicio']).between?(ini, fi) }
  end

  def avisos(chave, fim, dados_ate, lista)
    avisos = []
    avisos << { 'id' => 'dia_parcial', 'valores' => { 'dia' => fim.iso8601 } } if Autonomia::Desempenho::Conta.dia_de(dados_ate) == fim.iso8601
    avisos << { 'id' => 'so_periodo_todo', 'valores' => { 'secoes' => SECOES_FIXAS } } unless chave == 'tudo'
    avisos << { 'id' => 'pouco_dado', 'valores' => { 'n' => lista.size } } if lista.size < POUCO_DADO
    avisos << { 'id' => 'sem_anuncio', 'valores' => {} } unless anuncios_ligados?
    avisos
  end
end
