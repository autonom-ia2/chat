# A PROPOSTA DE UMA SEGURADORA SÓ (entrega 8 do Agente de Cotação, #396).
#
# O cliente leu a lista de preços e escolheu: "me manda a da Porto". Até 12/09/2026 o único caminho
# até `quote/proposal` era o comparativo — todas as seguradoras, sem código —, e a instrução do
# principal mandava ESCALAR em "gostei dessa". A proposta da seguradora escolhida é um PDF que o
# portal já gera com o filtro (`insurerCode`); o que continua com pessoa é o que vem depois dela:
# emissão, vistoria, pagamento.
#
# O QUE ELA NÃO FAZ: não cota. Lê a última cotação DESTA CONVERSA que tem preço entregue, traduz o
# nome que o cliente falou no código pelo mapa que a própria cotação gravou
# (`InsuranceQuote::NOMES_KEY`, código -> nome como o portal escreveu) e pede ao portal a proposta
# daquele código. Duas seguradoras são dois arquivos na MESMA execução, e nenhuma cotação nova
# (termo 4): `quote_start` não é chamado daqui em caminho nenhum.
#
# O CASAMENTO DO NOME É COMPARAÇÃO DE DADOS (`Escolha`), não interpretação: quem entende a frase é o
# modelo, que escreve o nome no parâmetro; o código compara texto normalizado com o mapa. O que não
# casa, casa com mais de um ou não tem cotação de onde sair é RECUSA NOMEADA (`Recusas`), no turno
# (o modelo pergunta ao cliente, nenhuma execução aberta) e no envio (o cliente lê a mesma frase).
#
# ASSÍNCRONA, como a cotação: `quote/proposal` é uma chamada ao portal de até 60 s por seguradora
# (`Connector::Http::READ_TIMEOUT`), e o turno não espera isso. No turno (`precheck`) só o que é
# dado nosso: a cotação da conversa e o casamento dos nomes — o portal NUNCA é chamado dentro do
# turno. O portal é chamado em `start`, dentro do `AsyncRunJob`, com a sessão da conexão
# (`with_fresh_session`, como a cotação faz em `start`, `poll` e no comparativo — no job há tempo
# para o login que o turno não tem). `poll` entrega os arquivos (`EntregaDeArquivo`, o publicador da
# entrega 11 baixa e anexa) e ANOTA NA LINHA DA COTAÇÃO quais propostas saíram
# (`ToolRun#anotar_propostas!` -> `InsuranceQuote::PROPOSTAS_KEY`, que a medida da entrega 7 lê).
class Autonomia::Agents::Tools::Native::InsuranceProposal < Autonomia::Agents::Tools::Native::Base
  Quote = ::Autonomia::Agents::Tools::Native::InsuranceQuote
  PARAMETRO = 'seguradoras'.freeze
  # Duas por vez (termo 4). Cada proposta é uma chamada ao portal de até 60 s, fora do turno; o teto
  # não é dinheiro (a proposta não consome cotação) — é o tamanho de uma resposta que se lê.
  MAX_SEGURADORAS = 2
  NOME = 'Proposta'.freeze
  # As chaves do handle DESTA execução: as propostas que o portal gerou (`{code, name, url}`) e os
  # nomes das que ele recusou. Não se chamam `propostas` de propósito: esse nome é o da chave que
  # fica na LINHA DA COTAÇÃO (`InsuranceQuote::PROPOSTAS_KEY`, só códigos), e dois formatos sob o
  # mesmo nome em duas linhas é como uma medida passa a somar a linha errada sem ninguém notar.
  GERADAS = 'geradas'.freeze
  NAO_SAIU = 'nao_saiu'.freeze

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

  # -> Hash serializável (o handle). A mesma avaliação do turno — a conferência pode ter caído — e
  # então o portal, uma chamada por seguradora escolhida. Volta rápido para o job: submete e não espera.
  def start
    avaliar || gerar(escolha.codigos)
  end

  # -> Tools::Progress. Uma passada: entrega os arquivos, anota na cotação quais saíram, e acaba.
  # `attempt` é do contrato (`Base#poll`); aqui não há seguradora lenta para esperar.
  def poll(handle:, attempt:) # rubocop:disable Lint/UnusedMethodArgument
    return progress_class.done(deliveries: [handle['pedido']], handle: handle) if handle['pedido']

    propostas = Array(handle[GERADAS]).select { |proposta| proposta.is_a?(Hash) }
    return progress_class.failed('sem_proposta') if propostas.empty?

    anotar_na_cotacao(handle, propostas.pluck('code'))
    progress_class.done(deliveries: entregas(propostas, handle), handle: handle)
  end

  private

  # Um arquivo por proposta e, se o portal recusou alguma, o aviso dela por último.
  def entregas(propostas, handle)
    lista = propostas.map { |proposta| entrega(proposta, handle['sufixo']) }
    faltaram = Array(handle[NAO_SAIU])
    faltaram.any? ? lista + [nao_saiu(faltaram)] : lista
  end

  # -> o handle de recusa (`pedido`/`motivo`/`faltando`), ou nil quando há o que gerar.
  def avaliar
    recusar_entrada || recusar_escolha
  end

  def recusar_entrada
    return recusa('proposta_sem_seguradora', SEM_SEGURADORA, faltando: [PARAMETRO]) if nomes.empty?
    return recusa('proposta_acima_do_teto', ACIMA_DO_TETO, faltando: [PARAMETRO]) if nomes.size > MAX_SEGURADORAS

    recusa('proposta_sem_cotacao', SEM_COTACAO, faltando: []) if cotacao.nil?
  end

  def recusar_escolha
    return recusa('seguradora_ambigua', ambigua(escolha), faltando: [PARAMETRO]) if escolha.ambiguas.any?

    recusa('seguradora_nao_cotou', nao_cotou(escolha.nao_cotaram), faltando: [PARAMETRO]) if escolha.nao_cotaram.any?
  end

  # UMA CHAMADA POR SEGURADORA, cada uma com o seu código. O que o portal recusou como "não cotou"
  # (`:validation`) não apaga o que ele gerou para a outra: sai o arquivo que saiu, e o aviso da que
  # não saiu. Só quando NENHUMA sai é recusa — a mesma de quem pede uma seguradora que não cotou.
  def gerar(codigos)
    urls = codigos.index_with { |codigo| proposta(codigo) }
    sairam, nao_sairam = urls.keys.partition { |codigo| urls[codigo] }
    return recusa('seguradora_nao_cotou', nao_cotou(nomes_de(codigos)), faltando: [PARAMETRO]) if sairam.empty?

    { 'quote_id' => quote_id, 'cotacao_run_id' => cotacao.id, 'sufixo' => sufixo_do_arquivo,
      GERADAS => sairam.map { |codigo| { 'code' => codigo, 'name' => mapa[codigo].to_s, 'url' => urls[codigo] } },
      NAO_SAIU => nomes_de(nao_sairam) }
  end

  def nomes_de(codigos)
    codigos.map { |codigo| mapa[codigo].to_s }
  end

  # -> a URL do PDF daquela seguradora, ou nil quando o portal disse que ela não cotou. Qualquer
  # outra falha sobe: o job decide entre tentar de novo e desistir com a nossa frase.
  def proposta(codigo)
    resposta = sessions.with_fresh_session do |open_session|
      connector.quote_proposal(provider: connection.provider, session: open_session, quote_id: quote_id, insurer_code: codigo)
    end
    resposta.to_h['url'].presence || raise(::Autonomia::Insurance::Connector::Error.new(:protocol, 'proposta sem url'))
  rescue ::Autonomia::Insurance::Connector::Error => e
    raise unless e.kind == :validation

    Rails.logger.warn("[autonomia][insurance] portal recusou proposta account=#{account.id} seguradora=#{codigo}: nao cotou")
    nil
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

  # O REGISTRO É NA LINHA DA COTAÇÃO, não nesta: é a cotação que "virou proposta", e é lá que a
  # medida da entrega 7 lê. A linha é achada pelo id que `start` guardou, dentro da conta.
  def anotar_na_cotacao(handle, codigos)
    linha = ::Autonomia::Agents::ToolRun.find_by(id: handle['cotacao_run_id'], account_id: account.id, slug: Quote.slug)
    return linha.anotar_propostas!(codigos) if linha

    Rails.logger.warn("[autonomia][insurance] cotacao da proposta nao encontrada account=#{account.id} run=#{handle['cotacao_run_id']}")
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

  # A ÚLTIMA COTAÇÃO DA CONVERSA COM PREÇO ENTREGUE E COM O MAPA DE NOMES: a mais recente por id, seja
  # qual for o status — uma cotação supersedida por um pedido novo que ainda não tem preço continua
  # sendo a que o cliente leu. Sem `nomes_entregues` (cotação anterior à entrega 8) não há como casar
  # o nome, e a resposta é "não encontrei cotação": a instrução manda oferecer cotar de novo.
  def cotacao
    return @cotacao if defined?(@cotacao)

    @cotacao = conversation && cotacoes_com_preco.order(id: :desc).first
  end

  def cotacoes_com_preco
    entregues = Quote::DELIVERED_KEY
    ::Autonomia::Agents::ToolRun.where(account_id: account.id, conversation_id: conversation.id, slug: Quote.slug)
                                .where("handle->>'quote_id' IS NOT NULL")
                                .where("jsonb_typeof(handle->?) = 'array' AND jsonb_array_length(handle->?) > 0", entregues, entregues)
                                .where("jsonb_typeof(handle->?) = 'object'", Quote::NOMES_KEY)
  end

  # Código -> nome, como o portal escreveu e o cliente leu.
  def mapa
    @mapa ||= cotacao.handle[Quote::NOMES_KEY].to_h.transform_keys(&:to_s)
  end

  # Em ordem alfabética: o jsonb devolve as chaves na ordem dele (tamanho, depois bytes), que não é
  # ordem para uma pessoa ler.
  def cotaram
    mapa.values.sort_by { |nome| Escolha.normalizar(nome) }
  end

  def quote_id
    cotacao.handle['quote_id'].to_s
  end

  # O mesmo nome do comparativo (entrega 11): a placa que o cliente informou ou, sem ela, o ramo.
  def sufixo_do_arquivo
    produto = cotacao.handle['produto'].presence || Quote::AUTO
    veiculo = cotacao.arguments['vehicle']
    placa = produto == Quote::AUTO && veiculo.is_a?(Hash) ? veiculo['plate'] : nil
    Quote::Comparativo.sufixo_do_arquivo(placa: placa, produto: produto)
  end

  # A sessão é a da conexão, reusada (#330); `with_fresh_session` renova se o portal a recusar.
  def sessions
    @sessions ||= ::Autonomia::Insurance::Connections::Session.new(connection, connector: connector)
  end

  def connection
    @connection ||= ::Autonomia::Insurance::Connection.for_account(account).find(&:ready?) ||
                    raise(::Autonomia::Insurance::Connector::Error.new(:config, 'sem conexão pronta'))
  end

  def connector
    @connector ||= ::Autonomia::Insurance::Connector.client
  end

  def progress_class
    ::Autonomia::Agents::Tools::Progress
  end
end
