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
# a primeira, `poll` pede as pendentes e depois entrega os arquivos, também UM por passada — cada
# `EntregaDeArquivo` é um download de até 20 s (`PRAZO_SEGUNDOS`), e dois numa passada passariam
# dos 25 s que o Sidekiq dá ao job num shutdown. `poll` também ANOTA NA LINHA DA COTAÇÃO quais
# propostas saíram (`ToolRun#anotar_propostas!` -> `InsuranceQuote::PROPOSTAS_KEY`, que a medida da
# entrega 7 lê), e confere a cada passada se a origem ainda vale (`dead?`).
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
  PARCIAL = 'Não consegui gerar todas as propostas a tempo. As que chegaram estão aqui em cima.'.freeze
  INCERTO = 'Não consegui confirmar se a proposta foi gerada. Um atendente vai conferir e retomar daqui.'.freeze

  include Recusas
  include Origem
  include Geracao

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

  # -> Tools::Progress. UMA passada faz UMA coisa: pede ao portal a próxima seguradora pendente, OU
  # entrega o próximo arquivo (anotando na cotação que ele saiu). Antes de qualquer uma, confere se a
  # origem ainda vale: supersedida no caminho, o cliente lê que a cotação foi refeita, e nada sai.
  # `attempt` é do contrato (`Base#poll`); aqui não há seguradora lenta para esperar.
  def poll(handle:, attempt:) # rubocop:disable Lint/UnusedMethodArgument
    return progress_class.done(deliveries: [handle['pedido']], handle: handle) if handle['pedido']

    origem = fixar_origem(handle[ORIGEM])
    return progress_class.failed('cotacao_ausente') if origem.nil?
    return progress_class.done(deliveries: [recusar('cotacao_substituida', SUBSTITUIDA, onde: 'envio')]) if origem.dead?

    pendente = Array(handle[PENDENTES]).first
    return progress_class.running(handle: tentar(handle, pendente)) if pendente

    entregar(handle)
  end

  private

  # UM ARQUIVO POR PASSADA: `running` com o próximo que ainda não saiu; `done` com o último, seguido
  # do aviso de quem o portal não gerou. Uma passada repetida (o handle não gravou depois de
  # publicar) reencontra tudo enviado e encerra: a publicação é idempotente pelo conteúdo.
  def entregar(handle)
    geradas = Array(handle[GERADAS]).select { |proposta| proposta.is_a?(Hash) }
    return sem_nenhuma(handle) if geradas.empty?

    enviadas = Array(handle[ENVIADAS]).map(&:to_s)
    faltam = geradas.reject { |proposta| enviadas.include?(proposta['code'].to_s) }
    return progress_class.done(deliveries: aviso(handle), handle: handle) if faltam.empty?

    entregar_proxima(handle, faltam.first, enviadas, ultima: faltam.size == 1)
  end

  # O REGISTRO É NA LINHA DA COTAÇÃO, não nesta: é a cotação que "virou proposta", e é lá que a
  # medida da entrega 7 lê. Anotado quando o arquivo SAI, um código por passada, união no banco.
  def entregar_proxima(handle, proposta, enviadas, ultima:)
    codigo = proposta['code'].to_s
    cotacao.anotar_propostas!([codigo])
    proximo = handle.merge(ENVIADAS => enviadas + [codigo])
    arquivo = entrega(proposta, handle['sufixo'])
    return progress_class.running(deliveries: [arquivo], handle: proximo) unless ultima

    progress_class.done(deliveries: [arquivo] + aviso(handle), handle: proximo)
  end

  # NENHUMA saiu: o portal não gerou as que o cliente pediu (recusa nomeada, registrada daqui — o job
  # só registra a do `start`), ou o handle não tem proposta nem falha (defeito, e o job fecha com a
  # nossa frase).
  def sem_nenhuma(handle)
    faltaram = handle[NAO_SAIU].to_h.keys
    return progress_class.failed('sem_proposta') if faltaram.empty?

    progress_class.done(deliveries: [recusar('proposta_nao_gerada', nao_gerada(nomes_de(faltaram)), onde: 'envio')])
  end

  # O aviso de quem o portal não gerou, por último — quando alguma saiu.
  def aviso(handle)
    faltaram = handle[NAO_SAIU].to_h.keys
    faltaram.any? ? [nao_saiu(nomes_de(faltaram))] : []
  end

  # -> o handle de recusa (`pedido`/`motivo`/`faltando`), ou nil quando há o que gerar.
  def avaliar
    recusar_entrada || recusar_escolha
  end

  # A ORDEM IMPORTA. A origem MORTA é o motivo mais específico e vem primeiro: no job, a fixada que
  # um pedido novo supersedeu diz "a cotação foi refeita" — mesmo que a nova esteja correndo (no
  # turno a origem escolhida nunca está morta, e a conferência cai no caso seguinte). Depois, a
  # cotação nova em andamento vale antes de "não encontrei cotação": o cliente acabou de mandar
  # refazer, e a resposta certa é esperar por ela, não oferecer cotar de novo.
  def recusar_entrada
    return recusa('proposta_sem_seguradora', SEM_SEGURADORA, faltando: [PARAMETRO]) if nomes.empty?
    return recusa('proposta_acima_do_teto', ACIMA_DO_TETO, faltando: [PARAMETRO]) if nomes.size > MAX_SEGURADORAS
    return recusa('cotacao_substituida', SUBSTITUIDA, faltando: []) if cotacao&.dead?
    return recusa('cotacao_em_andamento', EM_ANDAMENTO, faltando: []) if cotacao_em_andamento?

    recusa('proposta_sem_cotacao', SEM_COTACAO, faltando: []) if cotacao.nil?
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
    nome = proposta['name'].to_s
    url = proposta['url'].to_s
    arquivo = ::Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: "#{NOME} #{nome.tr('/\\', '-')} — #{sufixo}.pdf",
                                                               legenda: "#{NOME} da #{nome}.", reserva: "#{NOME} da #{nome}:\n#{url}")
    return arquivo.to_h if arquivo.valida?

    Rails.logger.warn("[autonomia][insurance] proposta sem forma de arquivo account=#{account.id} defeito=#{arquivo.defeito}; vai como link")
    arquivo.reserva
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
