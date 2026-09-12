# A PROPOSTA DE UMA SEGURADORA SÓ (entrega 8 do Agente de Cotação, #396).
#
# O cliente leu a lista de preços e escolheu: "me manda a da Porto". Até 12/09/2026 o único caminho
# até `quote/proposal` era o comparativo — todas as seguradoras, sem código —, e a instrução do
# principal mandava ESCALAR em "gostei dessa". A proposta da seguradora escolhida é um PDF que o
# portal já gera com o filtro (`insurerCode`); o que continua com pessoa é o que vem depois dela:
# emissão, vistoria, pagamento.
#
# O QUE ELA NÃO FAZ: não cota. Lê a cotação DE ORIGEM — escolhida UMA vez, no aceite, entre as desta
# conversa com preço entregue, e fixada nos argumentos da execução (`Origem`) —, traduz o nome que o
# cliente falou no código pelo mapa que a própria cotação gravou (`InsuranceQuote::NOMES_KEY`, código
# -> nome como o portal escreveu) e pede ao portal a proposta daquele código. Duas seguradoras são
# dois arquivos na MESMA execução, e nenhuma cotação nova (termo 4): `quote_start` não é chamado
# daqui em caminho nenhum.
#
# O CASAMENTO DO NOME É COMPARAÇÃO DE DADOS (`Escolha`), não interpretação: quem entende a frase é o
# modelo, que escreve o nome no parâmetro; o código compara texto normalizado com o mapa. O que não
# casa, casa com mais de um ou não tem cotação de onde sair é RECUSA NOMEADA (`Recusas`), no turno
# (o modelo pergunta ao cliente, nenhuma execução aberta) e no envio (o cliente lê a mesma frase).
#
# ASSÍNCRONA, como a cotação: `quote/proposal` é uma chamada ao portal de até 60 s por seguradora
# (`Connector::Http::READ_TIMEOUT`), e o turno não espera isso. No turno (`precheck`) só o que é
# dado nosso: a cotação da conversa e o casamento dos nomes — o portal NUNCA é chamado dentro do
# turno. O portal é chamado no `AsyncRunJob`, UMA seguradora por passada (`Geracao`): `start` pede
# a primeira, e o `poll` ENTREGA o que já foi gerado antes de pedir a próxima pendente — um arquivo
# por passada, porque cada `EntregaDeArquivo` é um download de até 20 s (`PRAZO_SEGUNDOS`) e dois
# numa passada passariam dos 25 s que o Sidekiq dá ao job num shutdown. `poll` também ANOTA NA LINHA
# DA COTAÇÃO quais propostas saíram (`ToolRun#anotar_propostas!` -> `InsuranceQuote::PROPOSTAS_KEY`,
# que a medida da entrega 7 lê) — só as com MENSAGEM publicada —, e confere a cada passada se a
# origem ainda vale: não morta e ainda a ÚLTIMA cotação da conversa (`Origem`). A mesma conferência
# é refeita no encerramento por prazo e na publicação efetiva (`Publicacao#publicavel?`), que pode
# sair até 90 s depois da passada que a produziu.
class Autonomia::Agents::Tools::Native::InsuranceProposal < Autonomia::Agents::Tools::Native::Base
  Quote = ::Autonomia::Agents::Tools::Native::InsuranceQuote
  PARAMETRO = 'seguradoras'.freeze
  # Duas por vez (termo 4). Cada proposta é uma chamada ao portal de até 60 s, fora do turno; o teto
  # não é dinheiro (a proposta não consome cotação) — é o tamanho de uma resposta que se lê.
  MAX_SEGURADORAS = 2
  NOME = 'Proposta'.freeze

  DESCRICAO = 'Gera o PDF da PROPOSTA de UMA seguradora que já cotou nesta conversa, para o cliente ' \
              'que escolheu ("me manda a da Porto"). Não cota de novo e não é o comparativo de ' \
              'todas: é o arquivo daquela seguradora só. Use quando o cliente pedir a proposta de ' \
              'uma ou duas seguradoras que apareceram na lista de preços. Não serve para emitir, ' \
              'contratar ou pagar — isso continua com um atendente.'.freeze
  # NÃO PROMETA O QUE AINDA NÃO ACONTECEU: este texto volta ao modelo antes de qualquer chamada ao
  # portal (a mesma lição do `ACEITA` da cotação).
  ACEITA = 'Você recebeu o pedido e já está buscando o arquivo da proposta. Diga isso ao cliente ' \
           'com as SUAS palavras, e que ele chega nesta conversa em instantes. Não invente valores ' \
           'nem prazos, não use vocabulário de sistema e não prometa emissão: a proposta é o ' \
           'documento da seguradora; contratar continua com um atendente.'.freeze
  ESPERANDO = 'Estou gerando a proposta agora. Assim que o arquivo estiver pronto, mando aqui.'.freeze
  FALHOU = 'Não consegui gerar a proposta agora. Um atendente vai retomar daqui.'.freeze
  # "ENVIAR", E NÃO "GERAR" (rodada 5, P3 do revisor final): o fecho parcial também sai quando o
  # portal GEROU as duas e só uma coube na passada do encerramento — dizer "não consegui gerar" ali
  # é desmentir um arquivo que existe. Quem ficou pronta e não foi enviada é dita pelo nome, com o
  # que fazer (`Recusas#nao_enviada`); esta frase é o fecho, e vale para os dois casos.
  PARCIAL = 'Não consegui enviar todas as propostas a tempo. As que chegaram estão aqui em cima.'.freeze
  INCERTO = 'Não consegui confirmar se a proposta foi gerada. Um atendente vai conferir e retomar daqui.'.freeze

  include Recusas
  include Origem
  include Geracao
  include Publicacao
  include Fecho

  class << self
    def slug
      'proposta_da_seguradora'
    end

    def tool_name
      'Proposta da seguradora'
    end

    # Gerar a proposta é chamada ao portal de até 60 s por seguradora: o turno não espera.
    def async?
      true
    end

    def description
      DESCRICAO
    end

    # ARRAY OBRIGATÓRIO, em strict mode: um parâmetro fora de `required` deixa o agente MUDO
    # (`openai_schema_spec`). "Uma ou duas" é regra da ferramenta (`MAX_SEGURADORAS`), não do schema.
    def params
      [{ 'name' => PARAMETRO, 'type' => 'array', 'items' => 'string',
         'description' => 'Nomes das seguradoras escolhidas, um por item, no máximo dois, escritos ' \
                          'como apareceram na lista de preços desta conversa (ex.: ["Porto"] ou ' \
                          '["Porto", "Bp Assinatura"]). Se o cliente usou outro nome ("Porto Seguro"), ' \
                          'escreva o da lista.' }]
    end

    # Módulo ligado e conexão pronta — a mesma porta da cotação, porque a proposta sai dela.
    def available_for?(agent)
      Quote.available_for?(agent)
    end

    def accepted_message
      ACEITA
    end

    def waiting_message
      ESPERANDO
    end

    def failure_message
      FALHOU
    end

    def partial_message
      PARCIAL
    end

    def uncertain_message
      INCERTO
    end
  end

  # A CONFERÊNCIA DO TURNO: tudo o que dá para saber sem o portal — a lista de nomes, a cotação da
  # conversa e o casamento — responde AQUI, e nenhuma execução é aberta. O texto é o mesmo que o
  # cliente leria no envio; o modelo o parafraseia. -> `Conferencia` ou nil (segue para o aceite).
  def precheck
    recusada = avaliar
    recusada && conferencia(recusada['motivo'], recusada['pedido'], recusada['faltando'])
  end

  # -> Hash serializável (o handle). A mesma avaliação do turno, agora sobre a origem FIXADA (a
  # conferência pode ter caído; a origem pode ter morrido) — e então o portal, para a PRIMEIRA
  # seguradora escolhida. Volta para o job com as demais pendentes: uma chamada por passada.
  def start
    avaliar || iniciar(escolha.codigos)
  end

  # -> Tools::Progress. UMA passada faz UMA coisa: entrega o próximo arquivo que ainda não chegou ao
  # cliente, OU pede ao portal a próxima seguradora pendente — NESTA ORDEM (rodada 3, P2 do Codex).
  # Antes era o contrário, e com a segunda seguradora em tempo esgotado a execução gastava as
  # passadas nela até o prazo estourar: a proposta que já estava pronta nunca saía.
  #
  # Antes de qualquer uma, confere se a origem ainda vale (`Origem#origem_ainda_vale?`): morta, ou já
  # não sendo a última cotação da conversa, nada sai e o cliente lê o porquê. A mesma conferência é
  # refeita na publicação EFETIVA (`publicavel?`), que pode acontecer até 90 s depois desta passada.
  # `attempt` é do contrato (`Base#poll`); aqui não há seguradora lenta para esperar.
  def poll(handle:, attempt:) # rubocop:disable Lint/UnusedMethodArgument
    return progress_class.done(deliveries: [handle['pedido']], handle: handle) if handle['pedido']

    origem = fixar_origem(handle[ORIGEM])
    return progress_class.failed('cotacao_ausente') if origem.nil?
    return progress_class.done(deliveries: [recusar_substituicao]) unless origem_ainda_vale?

    entregar(confirmar(handle))
  end

  private

  # O QUE JÁ CHEGOU AO CLIENTE, e o registro na linha da COTAÇÃO — é ela que "virou proposta", e é lá
  # que a medida da entrega 7 lê. A fonte de verdade é a MENSAGEM publicada, não o handle: o job
  # publica ANTES de gravar o handle, e uma publicação que volta `blocked` (autorização caída, banco)
  # deixava o código anotado e o arquivo contado como enviado SEM existir mensagem nenhuma (Codex,
  # rodada 2, P2). `ENVIADAS` continua no handle como CACHE do que já foi anotado: a anotação é uma
  # escrita no banco, e repeti-la a cada passada seria ruído.
  def confirmar(handle)
    codigos = (geradas(handle) - nao_publicadas(handle)).map { |proposta| proposta['code'].to_s }
    anotados = Array(handle[ENVIADAS]).map(&:to_s)
    novos = codigos - anotados
    return handle if novos.empty?

    cotacao.anotar_propostas!(novos)
    handle.merge(ENVIADAS => anotados | codigos)
  end

  # UMA COISA POR PASSADA, GERADAS ANTES DAS PENDENTES: cada `EntregaDeArquivo` é um download de até
  # 20 s e cada pedido ao portal é uma chamada de até 60 s; as duas na mesma passada passariam dos
  # 25 s que o Sidekiq dá ao job num shutdown. A passada que reentrega o que a anterior não conseguiu
  # publicar é idempotente: o publicador reencontra a mensagem pelo token e não posta de novo.
  def entregar(handle)
    faltam = nao_publicadas(handle)
    pendente = Array(handle[PENDENTES]).first
    return progress_class.running(deliveries: [entrega(faltam.first, handle['sufixo'])], handle: handle) if faltam.any?
    return progress_class.running(handle: tentar(handle, pendente)) if pendente
    return sem_nenhuma(handle) if geradas(handle).empty?

    # Nada por entregar e nada pendente: o aviso de quem o portal não gerou, e o fim.
    progress_class.done(deliveries: aviso_de(handle[NAO_SAIU].to_h.keys), handle: handle)
  end

  def geradas(handle)
    Array(handle[GERADAS]).select { |proposta| proposta.is_a?(Hash) }
  end

  def nao_publicadas(handle)
    geradas(handle).reject { |proposta| publicada?(proposta, handle['sufixo']) }
  end

  # NENHUMA saiu: o portal não gerou as que o cliente pediu (recusa nomeada, registrada daqui — o job
  # só registra a do `start`), ou o handle não tem proposta nem falha (defeito, e o job fecha com a
  # nossa frase).
  def sem_nenhuma(handle)
    faltaram = handle[NAO_SAIU].to_h.keys
    return progress_class.failed('sem_proposta') if faltaram.empty?

    progress_class.done(deliveries: [recusar('proposta_nao_gerada', nao_gerada(nomes_de(faltaram)), onde: 'envio')])
  end

  # O aviso de quem não saiu, depois dos arquivos.
  def aviso_de(codigos)
    faltaram = codigos.map(&:to_s).uniq
    faltaram.any? ? [nao_saiu(nomes_de(faltaram))] : []
  end

  # -> o handle de recusa (`pedido`/`motivo`/`faltando`), ou nil quando há o que gerar.
  def avaliar
    recusar_entrada || recusar_escolha
  end

  # O que falta ANTES de olhar a cotação: o nome da seguradora e o teto de duas por vez.
  def recusar_entrada
    return recusa('proposta_sem_seguradora', SEM_SEGURADORA, faltando: [PARAMETRO]) if nomes.empty?
    return recusa('proposta_acima_do_teto', ACIMA_DO_TETO, faltando: [PARAMETRO]) if nomes.size > MAX_SEGURADORAS

    recusar_origem
  end

  # As três maneiras de não haver de onde tirar a proposta, da mais específica para a mais geral. A
  # ORDEM IMPORTA. A origem que não serve mais — morta, ou já não sendo a última cotação da conversa
  # — vem primeiro, e vale antes de "não encontrei cotação": o cliente acabou de mandar refazer, e a
  # resposta certa é esperar pelos preços novos, não oferecer cotar de novo. Depois, a diferença
  # entre "esta EXECUÇÃO não tem origem fixada" (anterior ao deploy) e "esta CONVERSA não tem
  # cotação": a primeira pede o pedido de novo, a segunda oferece cotar.
  def recusar_origem
    return recusa_da_substituicao if cotacao && !origem_ainda_vale?
    return recusa('proposta_sem_origem', SEM_ORIGEM, faltando: []) if sem_origem?

    recusa('proposta_sem_cotacao', SEM_COTACAO, faltando: []) if cotacao.nil?
  end

  # A ORIGEM DEIXOU DE SER A ÚLTIMA — e o que o cliente faz em seguida depende da recotação (rodada
  # 5). Com ela viva, ou encerrada COM preço, esperar é legítimo, e o texto é o de sempre. Encerrada
  # SEM preço nenhum, esperar é esperar para sempre: a frase diz isso e oferece cotar de novo. Dois
  # textos e dois motivos no registro; a regra que barra a origem antiga continua sendo UMA.
  def recusa_da_substituicao
    return recusa('recotacao_sem_preco', RECOTACAO_SEM_PRECO, faltando: []) if recotacao_sem_preco?

    recusa('cotacao_substituida', SUBSTITUIDA, faltando: [])
  end

  # A MESMA escolha no ENVIO (`poll`), onde a recusa vira entrega ao cliente e é registrada daqui.
  def recusar_substituicao
    return recusar('recotacao_sem_preco', RECOTACAO_SEM_PRECO, onde: 'envio') if recotacao_sem_preco?

    recusar('cotacao_substituida', SUBSTITUIDA, onde: 'envio')
  end

  def recusar_escolha
    return recusa('seguradora_ambigua', ambigua(escolha), faltando: [PARAMETRO]) if escolha.ambiguas.any?

    recusa('seguradora_nao_cotou', nao_cotou(escolha.nao_cotaram), faltando: [PARAMETRO]) if escolha.nao_cotaram.any?
  end

  def nomes_de(codigos)
    codigos.map { |codigo| mapa[codigo].to_s }
  end

  # A entrega de arquivo na forma serializada (é ela que atravessa o `Progress` e o job) — ou, se a
  # URL do portal não cabe na forma (o adapter só garante que é uma URL), a reserva com o link, como
  # o comparativo faz: a forma recusada não pode apagar a entrega.
  def entrega(proposta, sufixo)
    arquivo = arquivo_de(proposta, sufixo)
    return arquivo.to_h if arquivo.valida?

    Rails.logger.warn("[autonomia][insurance] proposta sem forma de arquivo account=#{account.id} defeito=#{arquivo.defeito}; vai como link")
    arquivo.reserva
  end

  # O arquivo de uma proposta — o mesmo objeto para ENTREGAR e para perguntar se ela JÁ FOI
  # PUBLICADA (a identidade dele é o que vira o token da mensagem). Montado na hora nos dois usos:
  # nada disto é guardado entre passadas.
  def arquivo_de(proposta, sufixo)
    nome = proposta['name'].to_s
    url = proposta['url'].to_s
    ::Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: "#{NOME} #{nome.tr('/\\', '-')} — #{sufixo}.pdf",
                                                     legenda: "#{NOME} da #{nome}.", reserva: "#{NOME} da #{nome}:\n#{url}")
  end

  # O que o modelo escreveu, sem vazios e sem repetição pelo texto normalizado ("Porto" e "porto"
  # são um pedido). A ordem é a dele.
  def nomes
    @nomes ||= Array(params[PARAMETRO]).map { |nome| nome.to_s.strip }.reject(&:blank?)
                                       .uniq { |nome| Escolha.normalizar(nome) }
  end

  def escolha
    @escolha ||= Escolha.escolher(nomes, mapa)
  end

  def progress_class
    ::Autonomia::Agents::Tools::Progress
  end
end
