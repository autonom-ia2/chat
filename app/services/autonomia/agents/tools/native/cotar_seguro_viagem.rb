# COTAR SEGURO VIAGEM (#3211): a ferramenta do agente contratado "Seguro Viagem Universal". Confere os dados da viagem
# (`SeguroViagem::Pedido`), confere os destinos na lista da Universal, cota (`Universal::Cliente#cotar`), monta os planos
# pela lista branca (`SeguroViagem::Planos`), guarda a cotação (`CotacaoDeViagem`) e marca o comparativo em PDF como
# cartão do turno (`SeguroViagem::EntregaDoComparativo.cartao`).
#
# O PDF SAI COM A RESPOSTA DO TURNO, NUNCA DAQUI (#3223): a ferramenta não posta nada. O cartão vai na âncora do turno, e
# quem posta é o `Operate::CartoesDoTurno`, depois da resposta e só quando ela saiu. O turno superado (o cliente escreveu
# de novo), calado ou respondido por uma pessoa não posta a resposta nem o PDF (`cartao_descartado`). E o turno que já
# está superado nem cota: `ReplyJob.turno_superado?`, o critério da hora de postar, antes de chamar a Universal.
#
# O modelo recebe só o resumo: código do plano, nome, preço em reais, preço por dia e por pessoa (#3226), parcelas, as
# três coberturas principais e se o plano é anual. Nunca comissão, markup nem ranking (R2): eles não saem de `Planos.de`.
#
# SÍNCRONA e NUNCA LEVANTA com a seguradora fora: o erro do cliente HTTP passa por `SeguroViagem::Falhas`, que deixa a
# nota para a equipe, registra a recusa e devolve ao modelo o que fazer. Toda outra recusa passa por `recusar`/`error`
# da `Base`, que registra (R5): sem o registro, a recusa trava a próxima escrita do turno.
class Autonomia::Agents::Tools::Native::CotarSeguroViagem < Autonomia::Agents::Tools::Native::Base
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Universal = Autonomia::Seguradoras::Universal
  # O nome de um país que o modelo escreve: mais que isso não é nome de país, e o selo da capa não comporta.
  TETO_DO_NOME_DO_PAIS = 60
  TURNO_SUPERADO = 'O cliente escreveu de novo e esta resposta não vai sair. Não cote agora.'.freeze
  SO_ANUAIS = 'Para esta viagem a seguradora só devolveu planos anuais (valem para todas as viagens do ano). Diga isso ' \
              'ao cliente ao mostrar os planos.'.freeze

  class << self
    include SeguroViagem::PortaDoContratado

    # ESCREVE: abre cotação na seguradora, grava a cotação e manda o PDF ao cliente.
    def escreve? = true

    def slug
      'cotar_seguro_viagem'
    end

    def tool_name
      'Cotar seguro viagem'
    end

    def description
      'Cota o seguro viagem na seguradora com os países do roteiro, as datas de ida e volta e a idade de cada ' \
        'viajante; o comparativo dos planos em PDF sai junto com a sua resposta. Devolve os planos com o código (P1, P2...), o ' \
        'preço total em reais, o preço por dia e por pessoa, o destaque (o mesmo do PDF), as parcelas, as coberturas ' \
        'principais e se o plano é anual. Chame só depois de o cliente confirmar todos os dados; nunca invente preço nem cobertura.'
    end

    def args_registraveis
      %w[destinos data_saida data_retorno motivo incluir_anuais]
    end

    def params
      [
        { 'name' => 'destinos', 'type' => 'array', 'items' => 'string', 'required' => true,
          'description' => 'Siglas ISO 3166 alfa-2 de cada país do roteiro com permanência. Viagem nacional: ["BR"].' },
        { 'name' => 'nomes_dos_destinos', 'type' => 'array', 'items' => 'string', 'required' => false,
          'description' => 'O nome de cada país no idioma da conversa, como o cliente lê (ex.: França), na mesma ordem ' \
                           'de destinos.' },
        { 'name' => 'data_saida', 'type' => 'string', 'required' => true, 'description' => 'Data de ida, AAAA-MM-DD.' },
        { 'name' => 'data_retorno', 'type' => 'string', 'required' => true, 'description' => 'Data de volta, AAAA-MM-DD.' },
        { 'name' => 'idades', 'type' => 'array', 'items' => 'integer', 'required' => true,
          'description' => 'Idade de cada viajante, um inteiro por pessoa, na ordem em que o cliente informou.' },
        { 'name' => 'motivo', 'type' => 'string', 'required' => false, 'enum' => %w[lazer estudo negocios gestante cruzeiro],
          'description' => 'Só quando o cliente contou: gestante, estudo, negocios ou cruzeiro. Sem indicação, null.' },
        { 'name' => 'incluir_anuais', 'type' => 'boolean', 'required' => false,
          'description' => 'true só quando o cliente contou que viaja várias vezes no ano ou pediu plano anual ou ' \
                           'multiviagem. Sem isso, false: os planos anuais ficam fora da cotação e do PDF.' }
      ]
    end
  end

  def call
    return error('cotacao_sem_conversa') if conversa.nil?

    pedido_da_universal, falta = conferencia.conferir
    return recusar('pedido_invalido', falta.texto, faltando: [falta.campo]) if falta

    return recusar('turno_superado', TURNO_SUPERADO) if turno_superado?

    ok, invalidas = Universal::Destinos.validas_em?(pedido_da_universal['destinos'], paises)
    unless ok
      return recusar('destino_invalido', "Destino não reconhecido pela seguradora: #{invalidas.join(', ')}. Confirme o país " \
                                         'com o cliente.', faltando: ['destinos'])
    end

    cotar(pedido_da_universal)
  end

  private

  def cotar(pedido_da_universal)
    resposta = cliente.cotar(pedido_da_universal)
    candidatos = SeguroViagem::Planos.candidatos(resposta)
    planos = SeguroViagem::Planos.para_idades(candidatos, idades, incluir_anuais: incluir_anuais?)
    return sem_planos(candidatos) if planos.empty?

    cotacao = guardar(resposta, planos, pedido_da_universal)
    delivery.trocar_cartao(SeguroViagem::EntregaDoComparativo.cartao(cotacao)) # um comparativo por turno: o da última
    JSON.generate({ cotacao: cotacao.pedido.slice('destinos', 'data_saida', 'data_retorno', 'idades'),
                    planos: SeguroViagem::Planos.resumo(planos, cotacao.pedido), pdf_vai_junto: true,
                    **aviso_de_so_anuais(planos) })
  rescue Universal::Cliente::Erro => e
    SeguroViagem::Falhas.tratar(e, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  # Sem `incluir_anuais`, os anuais só voltam quando a seguradora não devolveu nenhum plano de viagem única: o modelo
  # precisa dizer isso ao cliente, que não pediu anual.
  def aviso_de_so_anuais(planos)
    return {} if incluir_anuais? || !SeguroViagem::Planos.so_anuais?(planos)

    { aviso: SO_ANUAIS }
  end

  # Uma mensagem mais nova do cliente já abriu outro turno: este não vai postar, e a cotação seria lida por ninguém. Só
  # no turno de uma mensagem do cliente (o da passagem e o de evento seguem). Com a conversa lida agora.
  def turno_superado?
    mensagem = delivery.origin_message_id
    mensagem.present? &&
      ::Autonomia::Agents::Operate::ReplyJob.turno_superado?(Conversation.find(conversa.id), mensagem, agent)
  end

  # Os candidatos ainda não passaram pela regra de idade: se há algum, o vazio é da idade.
  def sem_planos(candidatos)
    if candidatos.any?
      return recusar('idade_fora_do_limite', "Nenhum plano aceita as idades #{idades.join(', ')}. Avise o cliente e passe " \
                                             'para a equipe.', faltando: ['idades'])
    end

    recusar('sem_plano', 'A seguradora não devolveu plano para esta viagem. Passe a conversa para a equipe.')
  end

  # R4: os nossos parâmetros já conferidos (siglas em maiúsculas, datas ISO), o nome de cada país e, em 'universal', o
  # pedido enviado.
  def guardar(resposta, planos, pedido_da_universal)
    destinos = pedido_da_universal['destinos']
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversa, agent: agent, id_cotacao: resposta['idCotacao'], planos: planos,
      pedido: { 'destinos' => destinos, 'destinos_nomes' => nomes_dos_destinos(destinos),
                'data_saida' => pedido_da_universal['dataSaida'], 'data_retorno' => pedido_da_universal['dataRetorno'],
                'idades' => idades, 'motivo' => params['motivo'].presence, 'universal' => pedido_da_universal }
    )
  end

  # O nome de cada país como o cliente lê, escrito pelo modelo no idioma da conversa. Sem ele, com outro tamanho, ou
  # com algum nome em branco ou acima de `TETO_DO_NOME_DO_PAIS`, o nome da Universal (ou a sigla, com a lista de países
  # fora).
  def nomes_dos_destinos(destinos)
    nomes = params['nomes_dos_destinos']
    validos = nomes.is_a?(Array) && nomes.size == destinos.size && nomes.all? { |nome| nome_do_pais?(nome) }
    validos ? nomes.map(&:strip) : Universal::Destinos.nomes_em(destinos, paises)
  end

  def nome_do_pais?(nome)
    nome.is_a?(String) && nome.strip.present? && nome.strip.length <= TETO_DO_NOME_DO_PAIS
  end

  def conversa
    delivery.try(:conversation)
  end

  # O parâmetro chega tipado (`ParamsTipados`): só `true` inclui os anuais.
  def incluir_anuais?
    params['incluir_anuais'] == true
  end

  # O `Pedido` lê os parâmetros uma vez; as idades vêm dele, já inteiras.
  def conferencia
    @conferencia ||= SeguroViagem::Pedido.new(params, hoje: hoje, tarifa_acordo: acesso.tarifa_acordo?)
  end

  def idades
    conferencia.idades
  end

  # Os países da Universal, lidos uma vez por chamada: conferem os destinos e dão o nome de cada um. Com a Universal
  # fora nada fica no cache, e ler de novo seria outra chamada.
  def paises
    return @paises if defined?(@paises)

    @paises = Universal::Destinos.paises(cliente)
  end

  # O dia de hoje no fuso da conta: perto da meia-noite, o do servidor já seria amanhã.
  def hoje
    Crm::Timezone::Resolver.new(account: account).zone_or_default.today
  end

  def acesso
    agent.acesso_da_seguradora
  end

  def cliente
    @cliente ||= Universal::Cliente.new(login: acesso.login, senha: acesso.senha)
  end
end
