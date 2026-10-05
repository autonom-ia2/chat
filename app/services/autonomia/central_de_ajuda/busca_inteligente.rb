# A "Melhor resposta" da busca da Central (#977): o Jev (TypeSafe) escolhe, entre os artigos que a pessoa pode
# ler, o que responde ao que ela escreveu. Quem entende o pedido é o modelo; aqui só montamos a pergunta e
# conferimos a resposta. A busca por palavras (`Leitura#buscar`) continua sendo a reserva instantânea.
#
# A forma da pergunta é a "variante B" medida em 04/10/2026 (94% e 96% de acerto no 1º lugar contra 48% da
# busca por palavras): título, descrição e os sintomas do "O que dá errado" de cada artigo. Mudou a forma,
# meça de novo antes. O custo é NOSSO e fica em `Crm::AiUsageEvent` com a feature `central_busca`.
class Autonomia::CentralDeAjuda::BuscaInteligente
  FEATURE = 'central_busca'.freeze
  PERGUNTA = 'artigo'.freeze
  NENHUM = 'nenhum'.freeze
  INSTRUCOES = 'A pessoa escreveu isto na busca da Central de Ajuda de uma plataforma de atendimento e CRM. ' \
               'Qual artigo responde melhor ao que ela quer fazer ou ao problema que ela tem?'.freeze
  # A alternativa (#985) é uma segunda pergunta, sem o artigo já escolhido entre as opções: na mesma chamada o
  # Jev repetia a escolha 45 vezes em 79; em duas, o par acerta 77 de 79 (medido em 04/10/2026).
  INSTRUCOES_DA_ALTERNATIVA = 'A pessoa escreveu isto na busca da Central de Ajuda de uma plataforma de atendimento ' \
                              'e CRM. Qual artigo da lista também ajuda essa pessoa no que ela quer fazer ou no ' \
                              'problema que ela tem?'.freeze
  DESCRICAO_NENHUM = 'Nenhum artigo da lista responde ao que a pessoa escreveu.'.freeze
  MENOR_TERMO = 3
  MAIOR_TERMO = 200 # quem cola um texto enorme não multiplica o custo
  MAIOR_DESCRICAO = 600
  TEMPO_DE_LEITURA = 4 # segundos: a pessoa está esperando, e a busca por palavras já está na tela
  VALIDADE_DO_CACHE = 1.day
  SECAO_DOS_SINTOMAS = '## O que dá errado'.freeze
  INICIO_DO_SINTOMA = '- **"'.freeze
  FIM_DO_SINTOMA = '"**'.freeze
  # Marca o caractere que a transliteração não sabe converter (ela poria '?', e 😡 e 🙏 virariam a mesma chave).
  SEM_EQUIVALENTE = 0xFFFD.chr(Encoding::UTF_8).freeze # U+FFFD, o caractere de substituição

  RespostaInvalida = Class.new(StandardError)
  LimiteEstourado = Class.new(StandardError)

  # `limite` (LimiteDaBusca) é o teto de gasto da tela. Sem ele, só a avaliação interna (rake), que roda à mão.
  def initialize(leitura:, account:, limite: nil, client: nil, model: TypesafeAi::Config.model)
    @leitura = leitura
    @account = account
    @limite = limite
    @client = client
    @model = model
  end

  # { artigo: resumo, certeza: Float } ou nil quando não há escolha confiável. Com `exceto` (o id ou a ref da
  # Melhor resposta), devolve a alternativa: o artigo que também ajuda, fora o já escolhido. Um `exceto` que não é
  # artigo desta pessoa devolve nil: cair na pergunta normal devolveria a própria Melhor como "alternativa".
  def melhor(termo, exceto: nil)
    texto = termo.to_s.strip.first(MAIOR_TERMO)
    return unless pergunta_possivel?(texto)

    excluido = exceto.presence && exceto_valido(exceto)
    return if exceto.present? && excluido.nil?

    escolha = Rails.cache.fetch(chave_do_cache(texto, excluido), expires_in: VALIDADE_DO_CACHE) { perguntar(texto, excluido) }
    montar(escolha)
  rescue TypesafeAi::Client::Error, RespostaInvalida, LimiteEstourado => e
    # Erro não entra no cache (o bloco não terminou): a próxima busca tenta de novo.
    Rails.logger.warn("[central][busca_inteligente] falhou code=#{codigo_do_erro(e)} tamanho_do_termo=#{texto.length}")
    nil
  end

  private

  def pergunta_possivel?(texto)
    texto.length >= MENOR_TERMO && @leitura.artigos.any? && TypesafeAi::Config.configured?
  end

  def codigo_do_erro(erro)
    case erro
    when RespostaInvalida then 'resposta_invalida'
    when LimiteEstourado then 'limite'
    else erro.code
    end
  end

  def montar(escolha)
    return if escolha['choice'] == NENHUM

    artigo = @leitura.artigo(escolha['choice'])
    artigo && { artigo: @leitura.resumo(artigo), certeza: escolha['confidence'] }
  end

  # O teto só conta aqui, dentro do bloco do cache: resposta guardada não gasta nada.
  def perguntar(texto, excluido)
    raise LimiteEstourado if @limite && !@limite.permitir?

    comeco = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = client.evaluate(model: @model, state: { 'pergunta_da_pessoa' => texto },
                               questions: { PERGUNTA => { type: 'choice', instructions: instrucoes(excluido),
                                                          criteria: criterios(excluido) } })
    registrar_custo(response, comeco)
    validar(response, excluido)
  end

  # Mesma conferência do `TypesafeAi::Decisor#resultado`: modelo, tipo, certeza entre 0 e 1 e escolha entre as chaves.
  def validar(response, excluido)
    resposta = response.fetch('answers').fetch(PERGUNTA)
    certeza = resposta.fetch('confidence')
    escolha = resposta.fetch('choice')
    valido = response.fetch('model') == @model && resposta.fetch('type') == 'choice' && certeza_valida?(certeza) &&
             criterios(excluido).key?(escolha)
    raise RespostaInvalida unless valido

    { 'choice' => escolha, 'confidence' => certeza.to_f }
  rescue KeyError, TypeError, NoMethodError
    raise RespostaInvalida
  end

  def certeza_valida?(certeza) = certeza.is_a?(Numeric) && certeza.finite? && certeza.between?(0, 1)

  # Só vale um artigo que esta pessoa pode ler, pelo id ("02.04") ou pela ref ("02-04"), como a Leitura aceita.
  def exceto_valido(exceto)
    id = exceto.to_s.strip.tr('-', '.')
    id if id != NENHUM && criterios_de_todos.key?(id)
  end

  def instrucoes(excluido) = excluido ? INSTRUCOES_DA_ALTERNATIVA : INSTRUCOES

  # As opções da pergunta: todas, ou todas menos a Melhor resposta quando é a alternativa.
  def criterios(excluido) = excluido ? criterios_de_todos.except(excluido) : criterios_de_todos

  # Um critério por artigo que esta pessoa pode ler (a Leitura já filtrou por conta e papel), mais "nenhum".
  def criterios_de_todos
    @criterios_de_todos ||= @leitura.artigos.to_h { |artigo| [@leitura.central(artigo)['id'], descricao(artigo)] }
                                    .merge(NENHUM => DESCRICAO_NENHUM)
  end

  def descricao(artigo)
    lista = sintomas(artigo.content)
    texto = "#{artigo.title}. #{artigo.description}"
    texto += " Problemas comuns: #{lista.join('; ')}" if lista.any?
    texto.first(MAIOR_DESCRICAO)
  end

  # Os itens `- **"frase da pessoa"** ...` da seção "O que dá errado" do nosso próprio markdown.
  def sintomas(conteudo)
    secao(conteudo).filter_map do |linha|
      texto = linha.strip
      next unless texto.start_with?(INICIO_DO_SINTOMA)

      texto.delete_prefix(INICIO_DO_SINTOMA).split(FIM_DO_SINTOMA, 2).first
    end
  end

  def secao(conteudo)
    linhas = conteudo.to_s.lines
    inicio = linhas.index { |linha| linha.strip == SECAO_DOS_SINTOMAS }
    return [] unless inicio

    linhas[(inicio + 1)..].take_while { |linha| !linha.start_with?('## ') }
  end

  # Tudo o que muda a resposta entra na chave: modelo, a forma da pergunta e os critérios (conta com outra
  # visibilidade, ou artigo editado, pergunta de novo). Mudar a instrução invalida o cache sozinho.
  def chave_do_cache(texto, excluido)
    digest_pergunta = Digest::SHA256.hexdigest([instrucoes(excluido), PERGUNTA, criterios(excluido)].to_json)
    digest_termo = Digest::SHA256.hexdigest(normalizar(texto))
    "autonomia/central_de_ajuda/busca_inteligente/#{@model}/#{digest_pergunta}/#{digest_termo}"
  end

  # "Não  CONECTA" e "nao conecta" dividem a resposta. Se algum caractere não tem equivalente sem acento
  # (emoji, árabe, chinês), a chave usa o texto original: nunca uma versão que perdeu informação.
  def normalizar(texto)
    minusculo = texto.downcase.unicode_normalize(:nfkc)
    dobrado = I18n.transliterate(minusculo, replacement: SEM_EQUIVALENTE)
    (dobrado.include?(SEM_EQUIVALENTE) ? minusculo : dobrado).split.join(' ')
  end

  def client
    @client ||= TypesafeAi::Client.new(read_timeout: TEMPO_DE_LEITURA, retry_limit: 0)
  end

  def registrar_custo(response, comeco)
    Crm::Ai::UsageRecorder.record(
      account: @account, feature: FEATURE, model: response['model'].presence || @model, usage: response['usage'],
      latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - comeco) * 1000).round
    )
  end
end
