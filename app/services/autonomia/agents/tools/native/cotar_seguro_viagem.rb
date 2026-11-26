# COTAR SEGURO VIAGEM (#3211): a ferramenta do agente contratado "Seguro Viagem Universal". Confere os dados da viagem
# (`SeguroViagem::Pedido`), confere os destinos na lista da Universal, cota (`Universal::Cliente#cotar`), monta os planos
# pela lista branca (`SeguroViagem::Planos`), guarda a cotação (`CotacaoDeViagem`) e posta o comparativo em PDF na
# conversa (`SeguroViagem::EntregaDoComparativo`).
#
# O modelo recebe só o resumo: código do plano, nome, preço em reais, parcelas, as três coberturas principais e se o
# plano é anual. Nunca comissão, markup nem ranking (R2): eles não saem de `Planos.de`.
#
# A MESMA VIAGEM NÃO É COTADA DUAS VEZES NO DIA (#3223): se este agente já cotou hoje (no fuso da conta), nesta
# conversa, a mesma viagem (`CotacaoDeViagem.da_mesma_viagem`), a ferramenta devolve essa cotação com `ja_cotada: true`,
# sem chamar a Universal; o PDF dela só é postado se ainda não estiver na conversa. A conferência não fica sob o lock
# da conversa: a cotação chama a Universal entre conferir e gravar, e o caso real foi um turno depois do outro.
#
# SÍNCRONA e NUNCA LEVANTA com a seguradora fora: o erro do cliente HTTP passa por `SeguroViagem::Falhas`, que deixa a
# nota para a equipe, registra a recusa e devolve ao modelo o que fazer. Toda outra recusa passa por `recusar`/`error`
# da `Base`, que registra (R5): sem o registro, a recusa trava a próxima escrita do turno.
class Autonomia::Agents::Tools::Native::CotarSeguroViagem < Autonomia::Agents::Tools::Native::Base
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Universal = Autonomia::Seguradoras::Universal

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
        'viajante, e manda ao cliente o comparativo dos planos em PDF. Devolve os planos com o código (P1, P2...), o ' \
        'preço total em reais, as parcelas, as coberturas principais e se o plano é anual. Chame só depois de o ' \
        'cliente confirmar todos os dados; a mesma viagem já cotada hoje nesta conversa volta como a mesma cotação ' \
        '(ja_cotada), sem outro PDF. Nunca invente preço nem cobertura.'
    end

    def args_registraveis
      %w[destinos data_saida data_retorno motivo]
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
          'description' => 'Só quando o cliente contou: gestante, estudo, negocios ou cruzeiro. Sem indicação, null.' }
      ]
    end
  end

  def call
    return error('cotacao_sem_conversa') if conversa.nil?

    pedido_da_universal, falta = conferencia.conferir
    return recusar('pedido_invalido', falta.texto, faltando: [falta.campo]) if falta

    repetida = Autonomia::Agents::CotacaoDeViagem.da_mesma_viagem(conversa.id, agent.id, viagem(pedido_da_universal),
                                                                  fuso: fuso)
    return responder(repetida, ja_cotada: true) unless repetida.nil?

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
    planos = SeguroViagem::Planos.para_idades(candidatos, idades)
    return sem_planos(candidatos) if planos.empty?

    responder(guardar(resposta, planos, pedido_da_universal), ja_cotada: false)
  rescue Universal::Cliente::Erro => e
    SeguroViagem::Falhas.tratar(e, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  # `pdf_enviado`: o PDF desta cotação está na conversa (já estava, ou foi postado agora).
  def responder(cotacao, ja_cotada:)
    pdf_enviado = SeguroViagem::EntregaDoComparativo.postar(conversation: conversa, cotacao: cotacao, agent: agent)
    JSON.generate({ cotacao: cotacao.pedido.slice('destinos', 'data_saida', 'data_retorno', 'idades'),
                    planos: SeguroViagem::Planos.resumo(cotacao.planos.to_a), pdf_enviado: pdf_enviado,
                    ja_cotada: ja_cotada })
  end

  # Os candidatos ainda não passaram pela regra de idade: se há algum, o vazio é da idade.
  def sem_planos(candidatos)
    if candidatos.any?
      return recusar('idade_fora_do_limite', "Nenhum plano aceita as idades #{idades.join(', ')}. Avise o cliente e passe " \
                                             'para a equipe.', faltando: ['idades'])
    end

    recusar('sem_plano', 'A seguradora não devolveu plano para esta viagem. Passe a conversa para a equipe.')
  end

  # R4: os nossos parâmetros já conferidos (a viagem), o nome de cada país e, em 'universal', o pedido enviado.
  def guardar(resposta, planos, pedido_da_universal)
    viagem = viagem(pedido_da_universal)
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversa, agent: agent, id_cotacao: resposta['idCotacao'], planos: planos,
      pedido: viagem.merge('destinos_nomes' => nomes_dos_destinos(viagem['destinos']), 'universal' => pedido_da_universal)
    )
  end

  # A viagem como a cotação guarda: siglas em maiúsculas, datas ISO, idades inteiras e o motivo.
  def viagem(pedido_da_universal)
    { 'destinos' => pedido_da_universal['destinos'], 'data_saida' => pedido_da_universal['dataSaida'],
      'data_retorno' => pedido_da_universal['dataRetorno'], 'idades' => idades, 'motivo' => params['motivo'].presence }
  end

  # O nome de cada país como o cliente lê, escrito pelo modelo no idioma da conversa. Sem ele, com outro tamanho ou com
  # algum nome em branco, o nome da Universal (ou a sigla, com a lista de países fora).
  def nomes_dos_destinos(destinos)
    nomes = params['nomes_dos_destinos']
    validos = nomes.is_a?(Array) && nomes.size == destinos.size &&
              nomes.all? { |nome| nome.is_a?(String) && nome.strip.present? }
    validos ? nomes.map(&:strip) : Universal::Destinos.nomes_em(destinos, paises)
  end

  def conversa
    delivery.try(:conversation)
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
    fuso.today
  end

  def fuso
    @fuso ||= Crm::Timezone::Resolver.new(account: account).zone_or_default
  end

  def acesso
    agent.acesso_da_seguradora
  end

  def cliente
    @cliente ||= Universal::Cliente.new(login: acesso.login, senha: acesso.senha)
  end
end
