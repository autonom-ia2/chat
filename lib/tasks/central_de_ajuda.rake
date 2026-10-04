namespace :central_de_ajuda do
  # Publica agora, sem esperar a primeira leitura depois do deploy. Mesma rotina do job, idempotente.
  #   bundle exec rails central_de_ajuda:publicar
  desc 'Publica lib/central_de_ajuda no portal "plataforma" da instalação'
  task publicar: :environment do
    resultado = Autonomia::CentralDeAjuda::Publicador.new.publicar!
    next puts('[central_de_ajuda] outra publicação em curso; nada feito') if resultado.nil?

    puts "[central_de_ajuda] #{resultado}"
    resultado.falhas.each { |caminho| puts "  falhou: #{caminho}" }
    exit(1) unless resultado.ok?
  end

  # Mede de novo o acerto da busca da Central contra docs/central-de-ajuda/busca/casos.json (#977).
  #   bundle exec rails "central_de_ajuda:avaliar_busca[1]"                    # só palavras, de graça
  #   AVALIAR_COM_JEV=1 bundle exec rails "central_de_ajuda:avaliar_busca[1]"  # + Melhor resposta, PAGO
  # Fora do CI de propósito: com o Jev, cada caso é uma chamada paga. Ver docs/central-de-ajuda/busca/README.md.
  desc 'Mede o acerto da busca da Central de Ajuda (palavras e, com AVALIAR_COM_JEV=1, a Melhor resposta)'
  task :avaliar_busca, [:conta_id] => :environment do |_, args|
    conta = Account.find(args.fetch(:conta_id))
    # Administrador vê todos os artigos que a conta libera: mede a lista inteira, não a de um papel.
    admin = conta.account_users.find_by(role: :administrator)
    abort('[central_de_ajuda] a conta não tem administrador para ler a Central') unless admin

    avaliacao = CentralDeAjudaAvaliacaoDaBusca
    leitura = Autonomia::CentralDeAjuda::Leitura.new(account: conta, account_user: admin)
    visiveis = leitura.artigos.map { |artigo| leitura.central(artigo)['id'] }
    casos = avaliacao.casos_visiveis(JSON.parse(File.read(avaliacao::CASOS)), visiveis)
    abort('[central_de_ajuda] nenhum caso tem artigo visível nesta conta (a Central foi publicada?)') if casos.empty?

    inteligente = avaliacao.preparar_jev(leitura, conta, casos.size) if ENV['AVALIAR_COM_JEV'] == '1'
    resultados = casos.map { |caso| avaliacao.medir(caso, leitura, inteligente) }
    puts avaliacao.relatorio(resultados, com_jev: inteligente.present?)
  end
end

# A régua da busca. O cálculo (`placar`) é separado de quem chama a busca, para o spec conferir a conta
# sem banco e sem Jev.
module CentralDeAjudaAvaliacaoDaBusca
  CASOS = Rails.root.join('docs/central-de-ajuda/busca/casos.json').to_s
  # Medido em 04/10/2026 com a variante B: a lista de artigos inteira vai em cada pergunta.
  TOKENS_POR_BUSCA = 20_700
  TOPO = 3
  NENHUM = 'nenhum'.freeze

  module_function

  # Caso cujo artigo esperado esta conta não vê não mede nada: sai, e os esperados ficam só os visíveis.
  def casos_visiveis(casos, visiveis)
    casos.filter_map do |caso|
      ok = caso['ok'] & visiveis
      caso.merge('ok' => ok) if ok.any?
    end
  end

  # Antes de gastar: quantos casos e quanto custa. Sem cache, senão a segunda rodada mede o cache e não o Jev;
  # o NullStore vale só para este processo, a produção não muda. Sem chave, o serviço devolve nil sempre e a
  # régua mediria "nenhum" em tudo: para antes. O custo de cada chamada entra no uso de IA da conta, como na tela.
  def preparar_jev(leitura, conta, quantidade)
    abort('[central_de_ajuda] TypeSafe sem chave configurada; rode sem AVALIAR_COM_JEV') unless TypesafeAi::Config.configured?

    preco = Crm::Ai::Pricing.rate(TypesafeAi::Config.model)[:input]
    custo = quantidade * TOKENS_POR_BUSCA * preco / 1_000_000.0
    puts format('[central_de_ajuda] %<n>d casos com o Jev, ~US$ %<custo>.4f (estimativa)', n: quantidade, custo: custo)
    Rails.cache = ActiveSupport::Cache::NullStore.new
    Autonomia::CentralDeAjuda::BuscaInteligente.new(leitura: leitura, account: conta)
  end

  def medir(caso, leitura, inteligente)
    palavras = leitura.buscar(caso['q']).pluck(:id)
    { q: caso['q'], ok: caso['ok'], conjunto: caso['conjunto'], palavras: palavras,
      melhor: inteligente && melhor_resposta(inteligente, caso['q']) }
  end

  # nil é "nenhum" ou falha do Jev (o serviço loga e devolve nil, como na tela); os dois contam como erro.
  # Exceção que escape do serviço também conta erro daquele caso, com o motivo, e a avaliação segue.
  def melhor_resposta(inteligente, termo)
    achado = inteligente.melhor(termo)
    return { id: NENHUM, certeza: nil } unless achado

    { id: achado[:artigo][:id], certeza: achado[:certeza] }
  rescue StandardError => e
    { id: "falhou (#{e.class})", certeza: nil }
  end

  def relatorio(resultados, com_jev:)
    resultados.group_by { |r| r[:conjunto] }.flat_map do |conjunto, lista|
      contagem = placar(lista, com_jev: com_jev)
      [linha_do_placar(conjunto, contagem, com_jev), *contagem[:erros].map { |erro| "    erro: #{erro}" }]
    end
  end

  def placar(resultados, com_jev:)
    total = resultados.size
    base = { total: total, palavras_no_1o: resultados.count { |r| r[:ok].include?(r[:palavras].first) },
             palavras_nos_3: resultados.count { |r| no_topo?(r[:palavras], r[:ok]) },
             vazios: resultados.count { |r| r[:palavras].empty? } }
    return base.merge(erros: resultados.reject { |r| no_topo?(r[:palavras], r[:ok]) }.map { |r| erro_das_palavras(r) }) unless com_jev

    base.merge(placar_do_jev(resultados))
  end

  def placar_do_jev(resultados)
    errados = resultados.reject { |r| r[:ok].include?(r[:melhor][:id]) }
    certezas = errados.filter_map { |r| r[:melhor][:certeza] }
    { jev_no_1o: resultados.size - errados.size,
      combinado_nos_3: resultados.count { |r| no_topo?(combinada(r), r[:ok]) },
      certeza_media_dos_erros: certezas.any? ? (certezas.sum / certezas.size).round(2) : nil,
      erros: errados.map { |r| erro_do_jev(r) } }
  end

  # O que a tela mostra: a escolha do Jev no topo (fora "nenhum"), depois as palavras, sem repetir.
  def combinada(resultado)
    ([resultado[:melhor][:id]] - [NENHUM] + resultado[:palavras]).uniq
  end

  def no_topo?(ids, esperados) = ids.first(TOPO).intersect?(esperados)

  def erro_das_palavras(resultado)
    "#{resultado[:q]} => #{resultado[:palavras].first(TOPO).inspect} (esperado #{resultado[:ok].join(', ')})"
  end

  def erro_do_jev(resultado)
    certeza = resultado[:melhor][:certeza]
    "#{resultado[:q]} => #{resultado[:melhor][:id]} (certeza #{certeza ? certeza.round(2) : '-'}; esperado #{resultado[:ok].join(', ')})"
  end

  def linha_do_placar(conjunto, placar, com_jev)
    total = placar[:total]
    texto = "#{conjunto}: #{total} casos | palavras: 1º #{pct(placar[:palavras_no_1o], total)}, " \
            "#{TOPO} primeiros #{pct(placar[:palavras_nos_3], total)}, vazios #{placar[:vazios]}"
    return texto unless com_jev

    "#{texto} | Jev: 1º #{pct(placar[:jev_no_1o], total)}, combinado #{TOPO} primeiros " \
      "#{pct(placar[:combinado_nos_3], total)}, certeza média dos erros #{placar[:certeza_media_dos_erros] || '-'}"
  end

  def pct(acertos, total) = "#{acertos}/#{total} (#{(100.0 * acertos / total).round}%)"
end
