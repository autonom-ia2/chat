# O Guia lendo conversas em lote (#3158, B8b): "revise as conversas com nota 1 e 2 desta semana e diga os motivos".
#
# `comecar` escolhe as conversas (`Revisoes::Selecao`, com a permissão de quem pergunta), cria a revisão e solta o
# `RevisaoJob`; o cartão do Guia mostra o andamento e, no fim, os motivos agrupados. Até 300 por vez; acima disso o
# cartão oferece ler as que faltam.
#
# `parar`: a pessoa para a revisão escrevendo no Guia, e quem decide é a IA (#3143), sem botão nem lista de palavras.
# Enquanto uma revisão anda, a pergunta leva o aviso dela (`Guide::Chat#bloco_revisao`).
#
# Cada conversa lida é uma chamada de IA paga pela conta (feature `guia_revisao` na Gestão IA). Sem teto e sem pedir
# confirmação, por decisão do Rodrigo em 23/11: o uso é do cliente e o gasto fica visível.
class Autonomia::Agents::Tools::Native::GuiaRevisarConversas < Autonomia::Agents::Tools::Native::Base
  REVISAO = ::Autonomia::Guide::Revisao
  SELECAO = ::Autonomia::Guide::Revisoes::Selecao
  ACOES = %w[comecar parar].freeze

  class << self
    # Não muda nada da conta: só lê conversas.
    def escreve? = false

    def slug
      'revisar_conversas'
    end

    def args_registraveis
      %w[acao de ate notas status]
    end

    def description
      'Lê várias conversas da conta, uma por uma, com IA, e agrupa o que achou (motivos de notas baixas, assuntos, ' \
        'reclamações). Até 300 por vez; o painel mostra o andamento e o resultado. Use quando a pessoa pedir para ' \
        'revisar, ler ou analisar conversas. acao parar: quando a pessoa pedir para parar a revisão em andamento.'
    end

    def params
      [
        { 'name' => 'acao', 'type' => 'string', 'enum' => ACOES, 'required' => false, 'description' => 'Sem valor, comecar.' },
        { 'name' => 'titulo', 'type' => 'string', 'required' => false,
          'description' => 'O que está sendo revisado, em até 6 palavras. Ex.: "Revisão das notas 1 e 2".' },
        { 'name' => 'pedido', 'type' => 'string', 'required' => false,
          'description' => 'O que a pessoa quer saber de cada conversa, com as palavras dela.' },
        { 'name' => 'de', 'type' => 'string', 'required' => false, 'description' => 'Primeiro dia, AAAA-MM-DD.' },
        { 'name' => 'ate', 'type' => 'string', 'required' => false, 'description' => 'Último dia, incluído, AAAA-MM-DD.' },
        { 'name' => 'notas', 'type' => 'array', 'items' => { 'type' => 'integer' }, 'required' => false,
          'description' => 'Só conversas com estas notas de satisfação (1 a 5). Aí o período vale para a data da nota.' },
        { 'name' => 'etiqueta', 'type' => 'string', 'required' => false, 'description' => 'O nome lido da etiqueta.' },
        { 'name' => 'caixa_id', 'type' => 'string', 'required' => false, 'description' => 'O id lido da caixa.' },
        { 'name' => 'agente_id', 'type' => 'string', 'required' => false, 'description' => 'O id lido de quem atende.' },
        { 'name' => 'status', 'type' => 'string', 'enum' => SELECAO::STATUS, 'required' => false }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador&.user.nil?

    @params['acao'].to_s == 'parar' ? parar : comecar
  rescue SELECAO::Recusado => e
    e.message
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][revisao] account=#{@operador&.account&.id} #{e.class}: #{e.message}")
    'Não consegui começar a revisão agora.'
  end

  private

  def comecar
    andando = REVISAO.de(@operador.account, @operador.user).andando.last
    return "Já há uma revisão em andamento: #{andando.resumo}. Ela precisa terminar ou parar antes de outra." if andando

    selecao = SELECAO.new(account: @operador.account, user: @operador.user, params: @params)
    ids = selecao.ids
    return "Nenhuma conversa atende a este filtro (#{periodo(selecao)})." if ids.empty?

    revisao = criar(selecao, ids)
    ::Autonomia::Guide::RevisaoJob.perform_later(revisao.id)
    @operador.revisao_iniciada(revisao)
    "Achei #{ids.size} conversas (#{periodo(selecao)}). Comecei a ler #{revisao.ate}; o painel mostra o andamento e o " \
      'resultado. Diga à pessoa quantas achou e o período que você entendeu; não invente motivos agora.'
  end

  def criar(selecao, ids)
    REVISAO.create!(account: @operador.account, user: @operador.user, turno_id: @operador.turno_id, status: REVISAO::NA_FILA,
                    titulo: @params['titulo'].to_s.squish.first(80).presence || 'Revisão de conversas',
                    pedido: @params['pedido'].to_s.squish.first(1_000).presence || 'Por que cada conversa teve esse resultado.',
                    selecao: selecao.selecao, ids: ids, limite: REVISAO::POR_VEZ, batimento_em: Time.current)
  end

  def parar
    revisao = REVISAO.de(@operador.account, @operador.user).andando.last
    return 'Não há revisão em andamento.' if revisao.nil?
    return "A revisão já tinha terminado: #{revisao.resumo}." unless revisao.parar!

    ::Autonomia::Guide::Revisoes::Semaforo.sair(revisao)
    "Parei a revisão: #{revisao.resumo}. Os motivos até aqui aparecem no painel."
  end

  def periodo(selecao)
    "#{selecao.de.strftime('%d/%m')} a #{selecao.ate.strftime('%d/%m')}"
  end

  def recusa_sem_contexto
    'Não consigo revisar conversas agora porque não sei quem está perguntando.'
  end
end
