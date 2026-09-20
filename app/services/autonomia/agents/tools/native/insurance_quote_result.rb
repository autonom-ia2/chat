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
# o nome, o valor com o período e o parcelamento, ou o desfecho e a categoria do motivo (`veiculo`, `regiao` ou
# nenhuma) de quem não fez proposta. Nunca texto do portal. O que ela devolveu fica registrado no turno
# (`Tools::Delivery#registrar_resultado`), e o `Answerer` confere a fala contra isso antes de ela sair
# (`ConferenciaDePrecos`).
#
# Sem contexto de entrega (Testar, Copiloto, playground) não há conversa para ler nem turno para conferir:
# erro nomeado, pelo registro de recusa.
class Autonomia::Agents::Tools::Native::InsuranceQuoteResult < Autonomia::Agents::Tools::Native::Base
  Resultado = ::Autonomia::Insurance::ResultadoDaCotacao
  Guardado = ::Autonomia::Insurance::ResultadoPorSeguradora
  Motivo = ::Autonomia::Insurance::MotivoDaRecusa

  # O código da recusa sem contexto de entrega (`Tools::Recusa::MOTIVOS`).
  SEM_CONTEXTO = 'lista_indisponivel_nesta_superficie'.freeze

  # Os textos ao modelo.
  SEM_COTACAO = 'Não há cotação nesta conversa para mostrar. Não invente preço nem seguradora.'.freeze
  NAO_CHEGOU = 'A última cotação desta conversa não chegou às seguradoras, e não há preço dela para mostrar. ' \
               'Não invente preço nem seguradora.'.freeze
  ENVIO_INCERTO = 'Não se confirmou se a última cotação desta conversa chegou às seguradoras, e não há preço dela ' \
                  'para mostrar; um atendente vai conferir. Não invente preço nem seguradora.'.freeze
  SEM_RESULTADO = 'O resultado da cotação desta conversa não ficou guardado para consulta. Não invente preço ' \
                  'nem seguradora; se o cliente quiser ver os preços de novo, ofereça chamar um atendente.'.freeze
  SEM_PRECO_AINDA = 'A cotação ainda está correndo e nenhum preço chegou até agora. Não invente preço nem ' \
                    'seguradora.'.freeze
  SEM_PRECO = 'Nenhuma seguradora fez proposta nesta cotação. Não invente preço nem seguradora.'.freeze
  NAO_ENCONTRADA = 'Nenhuma seguradora com esse nome está nesta cotação. Não liste as seguradoras: pergunte ao ' \
                   'cliente de qual ele fala.'.freeze
  NAO_ENCONTRADA_AINDA = 'Nenhuma seguradora com esse nome apareceu nesta cotação até agora, e ela ainda está ' \
                         'correndo. Não liste as seguradoras.'.freeze
  # Como a Lia usa os preços desta resposta: regra de conteúdo, e não frase, porque as palavras são dela.
  COMO_ESCREVER = 'Escreva você a resposta ao cliente, com o recorte que ele pediu: as mais baratas, uma ' \
                  'seguradora, só as mensais, o que for. Cada valor e cada nome de seguradora exatamente como ' \
                  'estão aqui, e o período sempre junto do valor. Não ordene um valor por mês contra um valor ' \
                  'total pelo número. Sem travessão.'.freeze
  COMPARATIVO_ENVIADO = 'O comparativo em PDF desta cotação, com todos os preços, já foi entregue ao cliente.'.freeze
  AINDA_CORRENDO = 'A cotação ainda está correndo: podem chegar mais preços.'.freeze
  HA_SEM_PROPOSTA = 'Algumas seguradoras não fizeram proposta: só fale delas se o cliente perguntar.'.freeze
  SEM_BONUS = 'Esta cotação foi feita sem a classe de bônus da apólice atual.'.freeze
  # O motivo de quem não fez proposta, por categoria (`Insurance::MotivoDaRecusa`). Nunca o texto do portal.
  MOTIVOS = {
    Motivo::VEICULO => 'Categoria do motivo: veiculo. A recusa foi pelo veículo cotado, e não se sabe qual ' \
                       'característica: conte com as suas palavras que ela não aceitou o veículo, sem acrescentar detalhe.',
    Motivo::REGIAO => 'Categoria do motivo: regiao. A recusa foi pela região, e não se sabe mais que isso: conte com ' \
                      'as suas palavras que ela não atende a região, sem acrescentar detalhe.'
  }.freeze
  SEM_MOTIVO = 'Categoria do motivo: nenhuma. Não há motivo que você possa contar: diga só que ela não fez proposta.'.freeze

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
      [{ 'name' => 'seguradora', 'type' => 'string', 'required' => false,
         'description' => 'Nome da seguradora que o cliente perguntou, como ele escreveu. Mais de uma: todos ' \
                          'os nomes neste mesmo campo. null para o resultado inteiro.' }]
    end

    # Sem o módulo de seguros ligado não há cotação a consultar. Não exige conexão pronta: lê o banco.
    def available_for?(agent)
      ::Autonomia::Insurance::Config.enabled?(agent.account)
    rescue StandardError
      false
    end
  end

  # -> o texto ao modelo. O mesmo texto fica registrado no turno para a conferência da fala.
  def call
    conversa = delivery&.conversation
    return ::Autonomia::Agents::Tools::Recusa.para_modelo(SEM_CONTEXTO, slug: self.class.slug, delivery: delivery, agente: agent) if conversa.nil?

    texto = resposta(conversa)
    delivery.registrar_resultado(dados_do_turno(texto))
    texto
  end

  private

  def seguradora
    params['seguradora'].to_s.strip.presence
  end

  # O RESUMO DA ENTRADA VEM JUNTO DOS PREÇOS (#515). Em 19/09/2026 o cliente perguntou "o bônus da
  # apólice foi considerado?" e a Lia escalou: ela via o desfecho de cada seguradora e não via com que
  # dados a cotação tinha sido pedida. Não vai nos estados em que não há cotação a ler (`texto_sem_leitura`):
  # lá o assunto é outro, e o resumo de um pedido que não chegou ao portal confundiria.
  def resposta(conversa)
    @resultado = Resultado.da_conversa(conversa.id)
    return SEM_COTACAO if @resultado.nil?

    sem_leitura = texto_sem_leitura
    return sem_leitura if sem_leitura

    [(seguradora ? por_seguradora : geral), entrada_da_cotacao].compact.join("\n")
  end

  # -> o resumo da entrada da MESMA execução cujo resultado está sendo lido, ou nil (outro ramo,
  # execução sem argumentos).
  def entrada_da_cotacao
    ::Autonomia::Insurance::EntradaDaCotacao.new(@resultado.run.arguments, schema: schema_de_auto).texto
  end

  # O nome de cada opção (a franquia, a seguradora anterior) sai do MESMO schema que montou o
  # formulário do especialista: o que o adapter entregou na sincronização e está guardado na conexão
  # (`VehicleLookup` já lê o tipo do veículo assim). Só o GUARDADO — esta ferramenta é síncrona e o
  # cliente está esperando; buscar no adapter aqui custaria até 10 s de espera por um nome. Sem
  # schema, a opção entra sem nome, e nunca como código.
  def schema_de_auto
    ::Autonomia::Insurance::Connection.for_account(agent.account).find(&:ready?)&.quote_schema(Resultado.cotacao::AUTO)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] schema de auto indisponível no resultado #{e.class}")
    nil
  end

  # O que a conferência precisa: o texto que o modelo recebeu, o nome de toda seguradora da cotação e se o
  # comparativo já foi entregue.
  def dados_do_turno(texto)
    ::Autonomia::Agents::ConferenciaDePrecos::Dados.new(texto: texto, seguradoras: @resultado&.nomes.to_a,
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
    codigos = @resultado.procurar(seguradora)
    return @resultado.correndo? ? NAO_ENCONTRADA_AINDA : NAO_ENCONTRADA if codigos.empty?

    partes = [contagem(@resultado.com_preco.size), *codigos.map { |codigo| fala(codigo) }]
    partes += avisos if @resultado.com_preco(codigos).any?
    partes.join("\n")
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

  # O que o modelo lê sobre UMA seguradora. `motivo:` falso tira a categoria de quem não fez proposta.
  def fala(codigo, motivo: true)
    nome = @resultado.nome(codigo)
    case @resultado.desfecho(codigo)
    when Guardado::COM_PRECO then "#{nome} fez proposta: #{@resultado.preco(codigo)}."
    when Guardado::AGUARDANDO then "#{nome} ainda não respondeu, e a cotação continua correndo."
    else ["#{nome} não fez proposta nesta cotação.", (MOTIVOS.fetch(@resultado.motivo(codigo), SEM_MOTIVO) if motivo)].compact.join(' ')
    end
  end
end
