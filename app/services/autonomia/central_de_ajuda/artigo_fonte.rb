# Um artigo da Central de Ajuda como está no repositório (`lib/central_de_ajuda/<cap>/<id>-<slug>.md`),
# pronto para virar um Article do Chatwoot. Só lê e transforma texto; não toca o banco.
#
# O arquivo tem um cabeçalho YAML entre duas linhas `---` e o corpo em Markdown. Na publicação:
#   - comentários HTML saem (especificação de print, anotações de revisão);
#   - print que ainda não existe em `public/central-de-ajuda/prints/` sai, para não virar imagem quebrada;
#   - `[02.04]` vira link para o artigo, com o título dele no lugar do número.
class Autonomia::CentralDeAjuda::ArtigoFonte
  PREFIXO_SLUG = 'plataforma-'.freeze
  PASTA_PRINTS = Rails.public_path.join('central-de-ajuda/prints')
  URL_PRINTS = '/central-de-ajuda/prints/'.freeze
  MARCA_PRINT = '![PRINT '.freeze
  CAMPOS_META = %w[id capitulo publico prioridade requer me_leve_ate_la assuntos conferido_em].freeze

  class FormatoInvalido < StandardError; end

  attr_reader :caminho, :cabecalho, :corpo

  def self.slug_de(id)
    "#{PREFIXO_SLUG}#{id.to_s.tr('.', '-')}"
  end

  # titulos: { '02.04' => 'Sua assinatura de mensagens', ... } — para trocar `[02.04]` pelo título.
  def initialize(caminho, titulos:)
    @caminho = caminho
    @titulos = titulos
    @cabecalho, @corpo = separar(File.read(caminho))
  end

  def id = cabecalho.fetch('id')
  def capitulo = cabecalho.fetch('capitulo')
  def titulo = cabecalho.fetch('titulo')
  def slug = self.class.slug_de(id)

  def conteudo
    @conteudo ||= linkar(sem_prints_ausentes(sem_comentarios(corpo))).strip
  end

  # O primeiro parágrafo de "O que é": a frase que responde a pergunta sozinha (kit, seção 7). Sai como
  # texto simples, sem negrito nem código, porque aparece em lista e em resultado de busca.
  def descricao
    secao = conteudo.split('## O que é', 2).last.to_s.split('## ', 2).first.to_s
    texto_simples(secao.strip.split("\n\n").first.to_s.tr("\n", ' ').squeeze(' '))
  end

  def meta
    cabecalho.slice(*CAMPOS_META).merge('sha' => sha)
  end

  # Muda quando muda qualquer coisa que a publicação grava: evita update (e updated_at falso) sem mudança.
  def sha
    @sha ||= Digest::SHA256.hexdigest([titulo, conteudo, descricao, cabecalho.slice(*CAMPOS_META).to_json].join("\0"))[0, 16]
  end

  private

  def separar(texto)
    raise FormatoInvalido, "#{caminho}: sem cabeçalho" unless texto.start_with?("---\n")

    fim = texto.index("\n---\n", 4)
    raise FormatoInvalido, "#{caminho}: cabeçalho sem fechamento" if fim.nil?

    cabecalho = YAML.safe_load(texto[4...fim])
    raise FormatoInvalido, "#{caminho}: cabeçalho não é um mapa" unless cabecalho.is_a?(Hash)

    [cabecalho, texto[(fim + 5)..]]
  end

  # "[Título](plataforma-02-04)" vira "Título"; negrito e código perdem a marcação.
  def texto_simples(texto)
    saida = +''
    resto = texto
    while (abre = resto.index('['))
      meio = resto.index('](', abre)
      fecha = meio && resto.index(')', meio)
      break unless fecha

      saida << resto[0...abre] << resto[(abre + 1)...meio]
      resto = resto[(fecha + 1)..]
    end
    (saida << resto).delete('*`')
  end

  def sem_comentarios(texto)
    saida = +''
    resto = texto
    while (inicio = resto.index('<!--'))
      saida << resto[0...inicio]
      fim = resto.index('-->', inicio)
      break resto = '' if fim.nil?

      resto = resto[(fim + 3)..]
    end
    saida << resto
  end

  def sem_prints_ausentes(texto)
    texto.lines.filter_map { |linha| linha_publicavel(linha) }.join
  end

  def linha_publicavel(linha)
    return linha unless linha.lstrip.start_with?(MARCA_PRINT)

    inicio = linha.index('](prints/')
    return if inicio.nil?

    arquivo = File.basename(linha[(inicio + 9)..].split(')').first.to_s)
    return unless arquivo.present? && File.exist?(PASTA_PRINTS.join(arquivo))

    # "PRINT 02.06-a: Menu da foto" é a marca de quem escreve; quem lê (e o leitor de tela) fica só com a legenda.
    marca = linha.index(MARCA_PRINT)
    legenda = linha[(marca + MARCA_PRINT.length)...inicio].split(': ', 2).last
    "#{linha[0...marca]}![#{legenda}](#{URL_PRINTS}#{arquivo})"
  end

  # Troca cada `[dd.dd]` por `[Título](plataforma-dd-dd)`. Numa linha de "Veja também" (`- [02.04] Título`),
  # o título que vinha depois do número sai, para não aparecer duas vezes.
  def linkar(texto)
    texto.lines.map { |linha| linkar_linha(linha) }.join
  end

  def linkar_linha(linha)
    saida = +''
    posicao = 0
    while posicao < linha.length
      ref = referencia_em(linha, posicao)
      if ref
        titulo = @titulos.fetch(ref) { raise FormatoInvalido, "#{caminho}: link para artigo inexistente #{ref}" }
        saida << "[#{titulo}](#{self.class.slug_de(ref)})"
        posicao += 7
        posicao += titulo.length + 1 if linha[posicao, titulo.length + 1] == " #{titulo}"
      else
        saida << linha[posicao]
        posicao += 1
      end
    end
    saida
  end

  # `[dd.dd]` que não seja já o texto de um link Markdown (`[dd.dd](...)`).
  def referencia_em(linha, posicao)
    trecho = linha[posicao, 7].to_s
    return unless trecho.length == 7 && trecho[0] == '[' && trecho[6] == ']'
    return if linha[posicao + 7] == '('

    numero = trecho[1, 5]
    numero if numero_de_artigo?(numero)
  end

  # "02.04": dois dígitos, ponto, dois dígitos.
  def numero_de_artigo?(numero)
    numero[2] == '.' && (numero[0, 2] + numero[3, 2]).chars.all? { |c| c.between?('0', '9') }
  end
end
