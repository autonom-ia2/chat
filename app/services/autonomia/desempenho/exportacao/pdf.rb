# PDF do painel de desempenho do agente (#2226), em paisagem 16:9 (960 × 540 pt), uma ideia por página.
#
# Recebe o painel de UM período (contrato v2, já validado por Contrato) e devolve os bytes do arquivo. Não lê banco
# nem depende de quem chama: o script local e, depois, o endpoint usam o mesmo serviço.
#
# Toda página tem a moldura: faixa azul-escura com o agente e o período, título e subtítulo, e o rodapé de 3 colunas
# com "Página N de T". O plano de páginas é calculado antes de desenhar, para a capa trazer o índice certo.
# As cores espelham os tokens claros do painel (uma cor por série, igual na tela, no PDF e na planilha).
class Autonomia::Desempenho::Exportacao::Pdf
  include Autonomia::Desempenho::Exportacao::Textos
  include Autonomia::Desempenho::Exportacao::Leituras
  include Autonomia::Desempenho::Exportacao::Pdf::Desenho
  include Autonomia::Desempenho::Exportacao::Pdf::Ranking
  include Autonomia::Desempenho::Exportacao::Pdf::Capa
  include Autonomia::Desempenho::Exportacao::Pdf::Evolucao
  include Autonomia::Desempenho::Exportacao::Pdf::Funil
  include Autonomia::Desempenho::Exportacao::Pdf::Temas
  include Autonomia::Desempenho::Exportacao::Pdf::Origem
  include Autonomia::Desempenho::Exportacao::Pdf::Horarios
  include Autonomia::Desempenho::Exportacao::Pdf::Qualidade
  include Autonomia::Desempenho::Exportacao::Pdf::Pessoa
  include Autonomia::Desempenho::Exportacao::Pdf::Perdas
  include Autonomia::Desempenho::Exportacao::Pdf::Acoes
  include Autonomia::Desempenho::Exportacao::Pdf::ComoLer
  include Autonomia::Desempenho::Exportacao::Pdf::Tabelas
  include Autonomia::Desempenho::Exportacao::Pdf::Fatias

  LARGURA = 960
  ALTURA = 540
  LATERAL = 28
  FAIXA = 34
  MARGEM = [FAIXA + 16, LATERAL, 34, LATERAL].freeze # topo, direita, base, esquerda
  FONTES = Relatorios::Pdf::FONTES
  COR = {
    tinta: '1C2024', apoio: '60646C', fraca: '8B8D98', linha: 'E8E8EC', navy: '0D2344', navy_texto: 'B8C4DA',
    branco: 'FFFFFF', fundo: 'F5F6F8', ressalva_fundo: 'FEFBE9', ressalva_borda: 'FFE3A2', total: 'E6F4FE'
  }.freeze
  SERIE = {
    'volume' => { barra: '0090FF', texto: '0D74CE', trilho: 'E6F4FE' },
    'preparo' => { barra: '6E56CF', texto: '6550B9', trilho: 'F4F0FE' },
    'resultado' => { barra: '12A594', texto: '008573', trilho: 'E0F8F3' },
    'alerta' => { barra: 'E54666', texto: 'CA244D', trilho: 'FEEAED' },
    'tempo' => { barra: 'FFC53D', texto: 'AB6400', trilho: 'FFF7C2' },
    'neutro' => { barra: '8B8D98', texto: '60646C', trilho: 'F0F0F3' }
  }.freeze
  ALINHAMENTOS_DO_RODAPE = %i[left center right].freeze
  SECOES_FIXAS = %i[capa evolucao funil temas origem horarios qualidade pessoa perdas acoes como_ler].freeze

  def initialize(painel, marca: nil)
    @painel = Autonomia::Desempenho::Exportacao::Contrato.validar!(painel)
    @marca = marca
  end

  def gerar
    novo_documento
    paginas.each_with_index do |pagina, index|
      @doc.start_new_page unless index.zero?
      desenhar(pagina, index + 1)
    end
    @doc.render
  end

  # Uma entrada por página: { secao:, parte:, de: } (parte de 1 a `de` quando a seção ocupa várias páginas).
  def paginas
    @paginas ||= plano.flat_map { |secao, total| (1..total).map { |parte| { secao: secao, parte: parte, de: total } } }
  end

  # Primeira e última página de uma seção (para o índice da capa).
  def paginas_da_secao(secao)
    numeros = paginas.each_index.select { |index| paginas[index][:secao] == secao }.map { |index| index + 1 }
    [numeros.first, numeros.last]
  end

  def largura
    @doc.bounds.width
  end

  def topo
    @doc.bounds.height
  end

  private

  def plano
    SECOES_FIXAS.map { |secao| [secao, paginas_fixas(secao)] } + plano_das_tabelas
  end

  def paginas_fixas(secao)
    case secao
    when :temas then paginas_de_temas
    when :acoes then paginas_de_acoes
    when :como_ler then 2
    else 1
    end
  end

  def desenhar(pagina, numero)
    moldura(numero)
    send("pagina_#{pagina[:secao]}", pagina)
  end

  # Título de 20pt, subtítulo e a pílula do período à direita; devolve o `cima` onde o conteúdo começa.
  def abrir_pagina(titulo, subtitulo, pagina = nil)
    titulo = "#{titulo} (#{pagina[:parte]}/#{pagina[:de]})" if pagina && pagina[:de] > 1
    escrever_pilha([[titulo, 0, { tamanho: 20, estilo: :semibold, altura: 24 }],
                    [subtitulo, 26, { tamanho: 9.5, tinta: :apoio, altura: 13 }]], 0, topo, largura - 200)
    pilula_do_periodo
    topo - 50
  end

  def pilula_do_periodo
    periodo = periodo_texto(meta['periodo'])
    tamanho = @doc.width_of(periodo, size: 8.5) + 14
    pilula(periodo, largura - tamanho, topo - 4, fundo: serie('volume', :trilho), tinta: serie('volume', :texto), tamanho: 8.5)
  end

  def moldura(numero)
    @doc.canvas do
      faixa(0, ALTURA, LARGURA, FAIXA, cor(:navy))
      escrever("#{meta.dig('agente', 'nome')} · #{t('pdf.desempenho')}", LATERAL, ALTURA - 11, 420,
               tamanho: 10, estilo: :semibold, tinta: :branco, altura: 13)
      direita = t('pdf.cabecalho_direita', periodo: periodo_texto(meta['periodo']), dados_ate: dia_hora(meta['dados_ate']))
      escrever(direita, LARGURA - LATERAL - 420, ALTURA - 12, 420, tamanho: 8.5, tinta: :navy_texto, alinhar: :right, altura: 12)
      rodape(numero)
    end
  end

  def rodape(numero)
    terco = (LARGURA - (2 * LATERAL)) / 3.0
    textos = [t('pdf.rodape_marca', marca: @marca.presence || t('pdf.marca')),
              t('pdf.rodape_fonte'),
              t('pdf.rodape_pagina', n: format('%02d', numero), total: format('%02d', paginas.size))]
    linha_fina(LATERAL, LARGURA - LATERAL, 24)
    textos.zip(ALINHAMENTOS_DO_RODAPE).each_with_index do |(texto, alinhar), index|
      escrever(texto, LATERAL + (index * terco), 17, terco, tamanho: 7.5, tinta: :fraca, alinhar: alinhar)
    end
  end

  # O plano mede as tabelas antes de desenhar; sem `gerar` ainda, mede num documento novo do mesmo tamanho.
  def documento
    @doc || novo_documento
  end

  def novo_documento
    @doc = Prawn::Document.new(page_size: [LARGURA, ALTURA], margin: MARGEM.dup,
                               info: { Title: "#{meta.dig('agente', 'nome')} · #{t('pdf.desempenho')}" })
    registrar_fontes
    @doc
  end

  def registrar_fontes
    @doc.font_families.update(
      'Inter' => {
        normal: FONTES.join('Inter-Regular.ttf').to_s, medium: FONTES.join('Inter-Medium.ttf').to_s,
        semibold: FONTES.join('Inter-SemiBold.ttf').to_s, bold: FONTES.join('Inter-Bold.ttf').to_s
      }
    )
    @doc.font 'Inter'
  end
end
