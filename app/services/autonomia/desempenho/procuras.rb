# As procuras lidas de um agente (#2251), no formato do contrato v2: `conversa` é o número que a pessoa vê na caixa
# (`display_id`, o do link da conversa), `inicio` vem no fuso da ficha ('AAAA-MM-DDTHH:MM'). A lista sai na ordem
# (conversa, procura), como no protótipo. Com `visiveis` (as conversas que a pessoa vê), só as procuras delas; com
# `faixa` (Time..Time), só as que começam nela: o painel lê do banco o período e o anterior, não o histórico todo.
class Autonomia::Desempenho::Procuras
  COLUNAS = %w[
    conversation_id ordem inicio_em teste quem_id origem_id anuncio_id pedido_id tema_id resultado_id qualidade_id
    marcos motivo_ids regra_ids perda_evitavel precisava_pessoa teve_pessoa dados
  ].freeze

  def initialize(account:, sujeito_type:, sujeito_id:, configuracao:, fuso:, visiveis: nil, faixa: nil) # rubocop:disable Metrics/ParameterLists
    @account = account
    @sujeito_type = sujeito_type
    @sujeito_id = sujeito_id
    @compra_ids = Array(configuracao['compra_pedidos']).to_set
    @fuso = fuso
    @visiveis = visiveis
    @faixa = faixa
  end

  def lista
    carregar
    @lista
  end

  # {display_id => conversation_id} das conversas que têm procura.
  def conversas
    carregar
    @conversas
  end

  # {[conversa, procura] => porquê da venda perdida}
  def por_que
    carregar
    @por_que
  end

  # {display_id => 'AAAA-MM-DD'}: o dia da primeira procura (sem as de teste) de cada conversa da lista, olhando o
  # histórico inteiro, para "conversas novas" da evolução não depender de a faixa carregada começar antes.
  def primeiras
    carregar
    @primeiras ||= escopo.where(teste: false, conversation_id: @conversas.values).joins(:conversation)
                         .group('conversations.display_id').minimum(:inicio_em)
                         .transform_values { |em| em.in_time_zone(@fuso).to_date.iso8601 }
  end

  # Os exemplos da ficha ({grupo => {id => [[conversation_id, ordem]]}}) com o número da caixa no lugar do id interno.
  def exemplos(referencias)
    display = conversas.invert
    (referencias || {}).transform_values do |por_id|
      por_id.transform_values do |chaves|
        Array(chaves).filter_map { |conversation_id, ordem| [display[conversation_id], ordem] if display.key?(conversation_id) }
      end
    end
  end

  private

  def carregar
    return if @lista

    na_faixa = @faixa ? escopo.where(inicio_em: @faixa) : escopo
    colunas = [Arel.sql('conversations.display_id'), *COLUNAS.map { |c| "autonomia_desempenho_procuras.#{c}" }]
    linhas = na_faixa.joins(:conversation).pluck(*colunas)
    @conversas = {}
    @por_que = {}
    @lista = linhas.map { |linha| procura(linha) }.sort_by { |p| [p['conversa'], p['procura']] }
  end

  def escopo
    todas = Autonomia::Desempenho::Procura.do_sujeito(@account, @sujeito_type, @sujeito_id)
    @visiveis ? todas.where(conversation_id: @visiveis.select(:id)) : todas
  end

  def procura(linha) # rubocop:disable Metrics/AbcSize
    display_id, *valores = linha
    c = COLUNAS.zip(valores).to_h
    @conversas[display_id] = c['conversation_id']
    @por_que[[display_id, c['ordem']]] = c.dig('dados', 'por_que')
    compra = @compra_ids.include?(c['pedido_id'])
    {
      'conversa' => display_id, 'procura' => c['ordem'], 'inicio' => c['inicio_em'].in_time_zone(@fuso).strftime('%Y-%m-%dT%H:%M'),
      'teste' => c['teste'], 'quem_id' => c['quem_id'], 'origem_id' => c['origem_id'], 'anuncio_id' => c['anuncio_id'],
      'pedido_id' => c['pedido_id'], 'tema_id' => c['tema_id'], 'cortes' => c.dig('dados', 'cortes') || {},
      'marcos' => c['marcos'], 'resultado_id' => c['resultado_id'], 'motivo_ids' => c['motivo_ids'],
      'qualidade_id' => c['qualidade_id'], 'regra_ids' => c['regra_ids'],
      # Perda evitável só vale dentro de compra, como na definição.
      'perda_evitavel' => c['perda_evitavel'] && compra, 'precisava_pessoa' => c['precisava_pessoa'],
      'teve_pessoa' => c['teve_pessoa'], 'resumo' => c.dig('dados', 'resumo'), 'compra' => compra
    }
  end
end
