# COTAR SEGURO VIAGEM (#3211): a ferramenta do agente contratado "Seguro Viagem Universal". Confere os dados da viagem
# (`SeguroViagem::Pedido`), confere os destinos na lista da Universal, cota (`Universal::Cliente#cotar`), monta os planos
# pela lista branca (`SeguroViagem::Planos`), guarda a cotação (`CotacaoDeViagem`) e posta o comparativo em PDF na
# conversa (`SeguroViagem::EntregaDoComparativo`).
#
# O modelo recebe só o resumo: código do plano, nome, preço em reais, parcelas e as três coberturas principais. Nunca
# comissão, markup nem ranking (R2): eles não saem de `Planos.de`.
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
        'preço total em reais, as parcelas e as coberturas principais. Chame só depois de o cliente confirmar todos os ' \
        'dados; nunca invente preço nem cobertura.'
    end

    def args_registraveis
      %w[destinos data_saida data_retorno motivo]
    end

    def params
      [
        { 'name' => 'destinos', 'type' => 'array', 'items' => 'string', 'required' => true,
          'description' => 'Siglas ISO 3166 alfa-2 de cada país do roteiro com permanência. Viagem nacional: ["BR"].' },
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

    cotacao = guardar(resposta, planos, pedido_da_universal)
    pdf_enviado = SeguroViagem::EntregaDoComparativo.postar(conversation: conversa, cotacao: cotacao, agent: agent)
    JSON.generate({ cotacao: cotacao.pedido.slice('destinos', 'data_saida', 'data_retorno', 'idades'),
                    planos: SeguroViagem::Planos.resumo(planos), pdf_enviado: pdf_enviado })
  rescue Universal::Cliente::Erro => e
    SeguroViagem::Falhas.tratar(e, acao: self.class.slug, agent: agent, conversation: conversa)
  end

  # Os candidatos ainda não passaram pela regra de idade: se há algum, o vazio é da idade.
  def sem_planos(candidatos)
    if candidatos.any?
      return recusar('idade_fora_do_limite', "Nenhum plano aceita as idades #{idades.join(', ')}. Avise o cliente e passe " \
                                             'para a equipe.', faltando: ['idades'])
    end

    recusar('sem_plano', 'A seguradora não devolveu plano para esta viagem. Passe a conversa para a equipe.')
  end

  # R4: os nossos parâmetros já conferidos (siglas em maiúsculas, datas ISO) e, em 'universal', o pedido enviado.
  def guardar(resposta, planos, pedido_da_universal)
    destinos = pedido_da_universal['destinos']
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversa, agent: agent, id_cotacao: resposta['idCotacao'], planos: planos,
      pedido: { 'destinos' => destinos, 'destinos_nomes' => Universal::Destinos.nomes_em(destinos, paises),
                'data_saida' => pedido_da_universal['dataSaida'], 'data_retorno' => pedido_da_universal['dataRetorno'],
                'idades' => idades, 'motivo' => params['motivo'].presence, 'universal' => pedido_da_universal }
    )
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
    Crm::Timezone::Resolver.new(account: account).zone_or_default.today
  end

  def acesso
    agent.acesso_da_seguradora
  end

  def cliente
    @cliente ||= Universal::Cliente.new(login: acesso.login, senha: acesso.senha)
  end
end
