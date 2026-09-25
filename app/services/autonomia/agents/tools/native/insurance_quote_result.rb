# A LIA VÊ O RESULTADO DA COTAÇÃO (fatia 2 do #420) E ESCREVE OS PREÇOS (fatia 3).
#
# Ferramenta SÍNCRONA do principal. Lê, no instante da pergunta, o que a cotação mais nova da conversa guardou
# por seguradora (`Insurance::ResultadoDaCotacao`), e não chama o portal.
#
# DEVOLVE TAMBÉM A ENTRADA (#515): o resumo, em português, dos dados com que aquela cotação foi pedida
# (`Insurance::EntradaDaCotacao`). Sem ele a Lia sabia o desfecho de cada seguradora e não sabia o que tinha
# sido enviado — em 19/09/2026 ela escalou um "o bônus da apólice foi considerado?" que a entrada respondia.
#
# DEVOLVE OS DADOS AO MODELO, e quem escreve ao cliente é a Lia (decisão do CEO, 18/09/2026): por seguradora,
# o nome, o valor com o período e o parcelamento, ou que ela não fez proposta. POR QUE NÃO FEZ NÃO SE CONTA AO CLIENTE
# (decisões do CEO de 23 e 24/09/2026, chat#612 e #638): nem recusa, nem instabilidade, nem prazo. A Lia diz só que a
# seguradora não trouxe proposta desta vez; o motivo vai para a equipe numa nota interna
# (`InsuranceQuote::NotaDaEquipe`). Nunca texto do portal. O que ela devolveu fica registrado no turno
# (`Tools::Delivery#registrar_resultado`), e o `Answerer` confere a fala contra isso antes de ela sair
# (`ConferenciaDePrecos`).
#
# Sem contexto de entrega (Testar, Copiloto, playground) não há conversa para ler nem turno para conferir:
# erro nomeado, pelo registro de recusa.
class Autonomia::Agents::Tools::Native::InsuranceQuoteResult < Autonomia::Agents::Tools::Native::Base
  Resultado = ::Autonomia::Insurance::ResultadoDaCotacao
  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora

  # O código da recusa sem contexto de entrega (`Tools::Recusa::MOTIVOS`).
  SEM_CONTEXTO = 'lista_indisponivel_nesta_superficie'.freeze

  # Os textos ao modelo.
  SEM_COTACAO = 'Não há cotação nesta conversa para mostrar. Não invente preço nem seguradora.'.freeze
  NAO_CHEGOU = 'A última cotação desta conversa não chegou às seguradoras, e não há preço dela para mostrar. ' \
               'Não invente preço nem seguradora.'.freeze
  ENVIO_INCERTO = 'Não se confirmou se a última cotação desta conversa chegou às seguradoras, e não há preço dela ' \
                  'para mostrar. Diga que não conseguiu confirmar e que vai encaminhar para alguém da equipe conferir, sem ' \
                  'oferecer cotar de novo, e não invente preço nem seguradora.'.freeze
  SEM_RESULTADO = 'O resultado da cotação desta conversa não ficou guardado para consulta. Não invente preço ' \
                  'nem seguradora, e não ofereça cotar de novo só para rever preços.'.freeze
  SEM_PRECO_AINDA = 'A cotação ainda está correndo e nenhum preço chegou até agora. Não invente preço nem ' \
                    'seguradora.'.freeze
  SEM_PRECO = 'Nenhuma seguradora fez proposta nesta cotação. Não invente preço nem seguradora.'.freeze
  # A LISTA FECHADA (chat#718): quem escolhe a seguradora é o modelo, pelo nome exato da lista da cotação. Nome fora
  # dela volta com a lista, para ele escolher; se o cliente não falou de nenhuma, a saída é perguntar a ele.
  NAO_ENCONTRADA = 'Nenhum nome pedido é, exatamente, o de uma seguradora desta cotação. As seguradoras desta cotação ' \
                   'são: %<nomes>s. Se o cliente falou de uma delas, chame de novo com seguradoras igual ao nome dela, ' \
                   'escrito exatamente como está aqui. Se não falou de nenhuma, pergunte a ele de qual fala, sem listar ' \
                   'as seguradoras.'.freeze
  NAO_ENCONTRADA_AINDA = 'Nenhum nome pedido é, exatamente, o de uma seguradora desta cotação até agora, e ela ainda corre. ' \
                         'As de até agora: %<nomes>s. Se o cliente falou de uma, chame de novo com o nome dela exato.'.freeze
  # Parte dos nomes pedidos está na lista e parte não: o que ficou de fora, e a lista para escolher.
  FORA_DA_LISTA = 'Estes nomes não são, exatamente, os de uma seguradora desta cotação: %<fora>s. As seguradoras desta ' \
                  'cotação são: %<nomes>s.'.freeze
  # Como a Lia usa os preços desta resposta: regra de conteúdo, e não frase, porque as palavras são dela.
  COMO_ESCREVER = 'Escreva você a resposta ao cliente, com o recorte que ele pediu: as mais baratas, uma ' \
                  'seguradora, só as mensais, o que for. Cada valor e cada nome de seguradora exatamente como ' \
                  'estão aqui, e o período sempre junto do valor. Não ordene um valor por mês contra um valor ' \
                  'total pelo número. Sem travessão.'.freeze
  COMPARATIVO_ENVIADO = 'O comparativo em PDF desta cotação, com todos os preços, já foi entregue ao cliente.'.freeze
  AINDA_CORRENDO = 'A cotação ainda está correndo: podem chegar mais preços.'.freeze
  HA_SEM_PROPOSTA = 'Algumas seguradoras não fizeram proposta: só fale delas se o cliente perguntar.'.freeze
  SEM_BONUS = 'Esta cotação foi feita sem a classe de bônus da apólice atual.'.freeze
  # O que a Lia pode dizer de quem não fez proposta, seja qual for o motivo (chat#638).
  SEM_MOTIVO = 'Não há motivo que você possa contar: diga só que ela não trouxe proposta desta vez, sem falar de ' \
               'recusa, de risco, de aceitação, de prazo nem de instabilidade.'.freeze

  class << self
    def slug
      'ver_resultado_da_cotacao'
    end

    def tool_name
      'Ver resultado da cotação'
    end

    def description
      'Mostra o resultado da cotação desta conversa, com o que as seguradoras já responderam, sem cotar de ' \
        'novo. Use quando o cliente pedir para ver os preços outra vez, perguntar quanto deu uma seguradora, ' \
        'perguntar se uma seguradora fez proposta ou perguntar COM QUE DADOS a cotação foi feita (se o bônus ' \
        'da apólice entrou, qual franquia, qual CEP, se tem carro reserva). Devolve os preços, o que cada ' \
        'seguradora respondeu e um resumo da entrada com que a cotação foi pedida, para você escrever a resposta.'
    end

    def params
      [{ 'name' => 'seguradoras', 'type' => 'array', 'items' => 'string', 'required' => false,
         'description' => 'As seguradoras de que o cliente perguntou, cada nome escrito exatamente como a cotação o ' \
                          'escreve. null para o resultado inteiro, que traz o nome de todas.' },
       Resultado::PARAM_PRODUTO]
    end

    # Sem o módulo de seguros ligado não há cotação a consultar. Não exige conexão pronta: lê o banco.
    def available_for?(agent)
      ::Autonomia::Insurance::Config.enabled?(agent.account)
    rescue StandardError
      false
    end

    # A REFERÊNCIA DA FALA QUE NINGUÉM LEU NO TURNO (revisão adversarial de 24/09/2026). Quando a Lia escreve valor
    # sem que esta ferramenta tenha rodado no turno, a conferência compara com o que ela LERIA: o resultado guardado
    # da cotação mais nova de cada bem da conversa, no mesmo texto de `#call`, mais o que cada seguradora cotou.
    # `execucao`: a cotação do evento que acionou o turno (`Tools::Delivery#execucao_do_evento`); com preço, é ela a
    # referência, e não as outras da conversa. -> `ConferenciaDePrecos::Dados`, ou nil quando nenhuma tem preço.
    def referencia_guardada(conversa_id, agent:, execucao: nil)
      do_evento = execucao && new(agent: agent).dados_guardados(Resultado.new(execucao))
      return do_evento if do_evento

      partes = execucoes_com_resultado(conversa_id).filter_map { |run| new(agent: agent).dados_guardados(Resultado.new(run)) }
      return nil if partes.empty?

      # O comparativo só conta quando TODAS as cotações o entregaram: o recuo "está no PDF" não pode valer para o
      # bem que ficou sem ele.
      ::Autonomia::Agents::ConferenciaDePrecos::Dados.new(**partes.drop(1).sum(partes.first).to_h, comparativo: partes.all?(&:comparativo))
    end

    private

    # A mais nova de cada bem (a mesma que `#call` lê com `produto`), e a mais nova da conversa, que cobre a
    # execução anterior aos nomes de bem.
    def execucoes_com_resultado(conversa_id)
      faixas = Resultado.produtos(conversa_id)
      runs = faixas.filter_map { |faixa| Resultado.execucao_mais_nova(conversa_id, faixa: faixa) }
      [*runs, Resultado.execucao_mais_nova(conversa_id)].compact.uniq(&:id)
    end
  end

  # -> o texto ao modelo. Para a conferência da fala fica registrada SÓ A PARTE DOS PREÇOS.
  #
  # O RESUMO DA ENTRADA NÃO ENTRA NA CONFERÊNCIA (achado da revisão da PR #518). A conferência
  # autoriza a Lia a citar as seguradoras que aparecem nos dados do turno; o resumo cita a
  # SEGURADORA ANTERIOR da renovação, que também cota. Com ela nos dados, a fala "a HDI não fez
  # proposta" passaria sem nada que a sustentasse. Ao modelo o resumo vai inteiro; à conferência,
  # só o que fala de preço.
  def call
    conversa = delivery&.conversation
    return ::Autonomia::Agents::Tools::Recusa.para_modelo(SEM_CONTEXTO, slug: self.class.slug, delivery: delivery, agente: agent) if conversa.nil?

    precos = resposta(conversa)
    entrada = @resultado && !texto_sem_leitura ? entrada_da_cotacao : nil
    delivery.registrar_resultado(dados_do_turno(precos))
    [precos, entrada].compact.join("\n")
  end

  # O que `referencia_guardada` usa de uma cotação: o texto geral, que é o que `#call` devolve sem seguradora, e o
  # que cada seguradora com preço cotou, à parte (`coberturas`), como na pergunta por seguradora. -> nil sem preço.
  def dados_guardados(resultado)
    @resultado = resultado
    return nil if texto_sem_leitura || resultado.com_preco.empty?

    @coberturas = resultado.com_preco.filter_map do |codigo|
      cotou = resultado.cobertura(codigo)
      "O que #{resultado.nome(codigo)} cotou: #{cotou}." if cotou
    end
    dados_do_turno(geral)
  end

  private

  # Os nomes que o modelo escolheu, como ele os escreveu. [] para o resultado inteiro.
  def seguradoras = Array(params['seguradoras']).map { |nome| nome.to_s.squish }.compact_blank.uniq

  # Com mais de um bem cotado na conversa, quem lê precisa saber de qual é esta leitura e que os outros existem: em
  # 23/09/2026 a Lia leu a cotação nova do apartamento e disse que o carro "ainda não tem preços".
  def outros_produtos(conversa)
    produtos = Resultado.produtos(conversa.id)
    return nil if produtos.size < 2

    atual = @resultado.run.faixa.presence || Resultado.cotacao::AUTO
    outros = (produtos - [atual]).join('; ')
    "Esta é a cotação de #{atual}. A conversa também tem cotação de: #{outros}. Para ver outra, chame de novo com " \
      'produto igual ao nome dela.'
  end

  # O RESUMO DA ENTRADA VEM JUNTO DOS PREÇOS (#515). Em 19/09/2026 o cliente perguntou "o bônus da
  # apólice foi considerado?" e a Lia escalou: ela via o desfecho de cada seguradora e não via com que
  # dados a cotação tinha sido pedida. Não vai nos estados em que não há cotação a ler (`texto_sem_leitura`):
  # lá o assunto é outro, e o resumo de um pedido que não chegou ao portal confundiria.
  def resposta(conversa)
    escolha = Resultado.escolha(conversa.id, params, especialista)
    return escolha.pergunta if escolha.pergunta

    @resultado = Resultado.da_conversa(conversa.id, faixa: escolha.faixa)
    return SEM_COTACAO if @resultado.nil?

    sem_leitura = texto_sem_leitura
    return sem_leitura if sem_leitura

    [(seguradoras.any? ? por_seguradora : geral), outros_produtos(conversa)].compact.join("\n")
  end

  # -> o resumo da entrada da MESMA execução cujo resultado está sendo lido, ou nil (outro ramo,
  # execução sem argumentos).
  # Falha aqui não pode custar os preços ao cliente (achado da revisão): sem resumo, o modelo segue
  # com o que importa.
  def entrada_da_cotacao
    ::Autonomia::Insurance::EntradaDaCotacao.new(@resultado.run.arguments, schema: schema_do_produto).texto
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] resumo da entrada indisponível #{e.class}")
    nil
  end

  # O nome de cada opção (a franquia, a seguradora anterior) sai do MESMO schema que montou o
  # formulário do especialista: o que o adapter entregou na sincronização e está guardado na conexão
  # (`VehicleLookup` já lê o tipo do veículo assim). Só o GUARDADO — esta ferramenta é síncrona e o
  # cliente está esperando; buscar no adapter aqui custaria até 10 s de espera por um nome. Sem
  # schema, a opção entra sem nome, e nunca como código. O schema é o do produto desta cotação (residencial também
  # tem resumo, chat#323); `produto` em branco é auto.
  def schema_do_produto
    produto = @resultado.run.arguments.to_h.stringify_keys['produto'].to_s.strip.presence || Resultado.cotacao::AUTO
    ::Autonomia::Insurance::Connection.for_account(agent.account).find(&:ready?)&.quote_schema(produto)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] schema indisponível no resultado #{e.class}")
    nil
  end

  # O que a conferência precisa: o texto que o modelo recebeu, o nome de toda seguradora da cotação e se o
  # comparativo já foi entregue.
  # O que cada seguradora cotou vai à parte (`coberturas`): o valor de cobertura pode ser citado, mas não como preço.
  def dados_do_turno(texto)
    coberturas = Array(@coberturas)
    ::Autonomia::Agents::ConferenciaDePrecos::Dados.new(texto: texto.lines.map(&:chomp).reject { |linha| coberturas.include?(linha) }.join("\n"),
                                                        seguradoras: @resultado&.nomes.to_a, coberturas: coberturas,
                                                        comparativo: @resultado&.comparativo_enviado? || false)
  end

  # -> o texto de quando a cotação encerrada não tem resultado a ler, ou nil. A que ainda corre sem ter gravado
  # resultado (a linha em voo no deploy, ou a que nem consultou o portal) tem: "ainda sem preço". A encerrada
  # com envio incerto pode existir no portal; a encerrada sem número do portal não chegou às seguradoras; a
  # encerrada antes desta versão não guardou o resultado.
  def texto_sem_leitura
    return nil if @resultado.correndo?
    return ENVIO_INCERTO if @resultado.envio_incerto?
    return NAO_CHEGOU unless @resultado.cotou?

    SEM_RESULTADO unless @resultado.guardado?
  end

  # Todas as seguradoras: primeiro as com preço, na ordem da lista de preços, depois as demais, sem o motivo
  # (ele só vai quando o cliente pergunta por aquela seguradora, `por_seguradora`).
  def geral
    com_preco = @resultado.com_preco
    return @resultado.correndo? ? SEM_PRECO_AINDA : SEM_PRECO if com_preco.empty?

    outras = @resultado.codigos - com_preco
    [contagem(com_preco.size), *com_preco.map { |codigo| fala(codigo) },
     (HA_SEM_PROPOSTA if @resultado.sem_proposta?), *outras.map { |codigo| fala(codigo, motivo: false) },
     *avisos].compact.join("\n")
  end

  def por_seguradora
    escolhidos = seguradoras.index_with { |nome| @resultado.codigo_do_nome(nome) }
    codigos = escolhidos.values.compact.uniq
    return format(@resultado.correndo? ? NAO_ENCONTRADA_AINDA : NAO_ENCONTRADA, nomes: @resultado.lista_fechada) if codigos.empty?

    partes = [contagem(@resultado.com_preco.size), *codigos.map { |codigo| fala(codigo, cobertura: true) }, fora_da_lista(escolhidos)]
    partes += avisos if @resultado.com_preco(codigos).any?
    partes.compact.join("\n")
  end

  # Os nomes pedidos que não são de nenhuma seguradora da cotação, com a lista para escolher; nil sem nenhum.
  def fora_da_lista(escolhidos)
    fora = escolhidos.select { |_, codigo| codigo.nil? }.keys
    format(FORA_DA_LISTA, fora: fora.join('; '), nomes: @resultado.lista_fechada) if fora.any?
  end

  # O que acompanha os preços: a cotação ainda correndo, a renovação sem bônus, o comparativo já entregue e
  # como escrever.
  def avisos
    [(AINDA_CORRENDO if @resultado.correndo?), (SEM_BONUS if @resultado.sem_bonus?),
     (COMPARATIVO_ENVIADO if @resultado.comparativo_enviado?), COMO_ESCREVER].compact
  end

  # Quantas seguradoras fizeram proposta, sem nome e sem valor.
  def contagem(total)
    quando = @resultado.correndo? ? 'até agora' : 'nesta cotação'
    return "Nenhuma seguradora fez proposta #{quando}." if total.zero?

    "#{total} #{total == 1 ? 'seguradora fez' : 'seguradoras fizeram'} proposta #{quando}."
  end

  # O que o modelo lê sobre UMA seguradora. `motivo:` falso tira a regra de como falar de quem não fez proposta;
  # `cobertura:` verdadeiro acrescenta, na linha seguinte, o que ela cotou (chat#585), e só a pergunta por
  # seguradora a pede. A conferência recebe essa linha à parte (`dados_do_turno`).
  def fala(codigo, motivo: true, cobertura: false)
    nome = @resultado.nome(codigo)
    case @resultado.desfecho(codigo)
    when Guardado::COM_PRECO then com_preco(nome, codigo, cobertura)
    when Guardado::AGUARDANDO then "#{nome} ainda não respondeu, e a cotação continua correndo."
    else ["#{nome} não fez proposta nesta cotação.", (SEM_MOTIVO if motivo)].compact.join(' ')
    end
  end

  def com_preco(nome, codigo, cobertura)
    cotou = cobertura ? @resultado.cobertura(codigo) : nil
    linha = "O que #{nome} cotou: #{cotou}." if cotou
    (@coberturas ||= []) << linha if linha
    ["#{nome} fez proposta: #{@resultado.preco(codigo)}.", linha].compact.join("\n")
  end
end
