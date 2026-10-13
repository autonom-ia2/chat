# "Criar com IA" / "Melhorar com IA" da tela de Modelos (#1333) no padrão assíncrono do fork (`DeferInteractiveAi`):
# o controller confere o pedido (`entradas`, sem IA) e enfileira; o `Crm::Ai::InteractiveJob` chama `executar`, com 25 s
# e uma nova tentativa (a IA passa de 11 s numa parte dos pedidos), e a tela busca o resultado em GET ai_requests/:id.
#
#   Whatsapp::Templates::Sugestao.entradas(params)  # => { 'mode' => 'create', 'goal' => '...', ... } ou Redacao::Invalida
#   Whatsapp::Templates::Sugestao.executar(account:, inputs:)
#   # => { payload: { status:, question:, suggestions:, options: [...] } } ou { error: 'suggestion_unavailable', message: }
#
# O resultado nunca leva a exceção nem o texto do erro da IA: sem IA, IA fora do ar ou nenhuma opção boa é a frase
# simples, e a tela segue editável à mão.
class Whatsapp::Templates::Sugestao
  MODES = %w[create improve].freeze
  OPERACAO = 'whatsapp_template_suggestion'.freeze
  TIMEOUT = 25
  MAX_RETRIES = 1
  # A tela de Modelos (`whatsapp_templates_journey`) e o piloto da IA (`whatsapp_templates_ai`, conta 16; Refs #1450).
  FLAGS = %w[whatsapp_templates_journey whatsapp_templates_ai].freeze

  def self.liberada?(account)
    FLAGS.all? { |flag| account.feature_enabled?(flag) }
  end

  # Só o que o modo usa, já conferido, vai para o pedido guardado (Redis, 30 min, `Crm::Ai::InteractiveRequest`).
  def self.entradas(params)
    mode = params[:mode].to_s
    raise Whatsapp::Templates::Redacao::Invalida, 'mode' unless MODES.include?(mode)

    comum = { 'mode' => mode, 'tone' => escolha(params[:tone], Whatsapp::Templates::Redacao::TONS),
              'category' => escolha(params[:category], Whatsapp::Templates::Redacao::CATEGORIAS.keys) }
    return comum.merge('goal' => Whatsapp::Templates::Redacao.conferir_criar!(params[:goal])) if mode == 'create'

    texto = params[:text].to_s
    comum.merge('text' => texto, 'improvements' => Whatsapp::Templates::Redacao.conferir_melhorar!(texto, params[:improvements]),
                'meta_reason' => params[:meta_reason].to_s.first(Whatsapp::Templates::Redacao::MOTIVO_MAXIMO))
  end

  def self.escolha(valor, permitidos)
    permitidos.include?(valor.to_s) ? valor.to_s : ''
  end
  private_class_method :escolha

  def self.executar(account:, inputs:)
    new(account, inputs.to_h.stringify_keys).executar
  end

  def initialize(account, inputs)
    @account = account
    @inputs = inputs
  end

  def executar
    result = escrever
    return indisponivel if result[:status] == 'ok' && result[:opcoes].empty?

    { payload: { status: result[:status], question: result[:pergunta], suggestions: result[:sugestoes],
                 options: result[:opcoes].map { |opcao| opcao_json(opcao) } } }
  rescue Ai::Redacao::Escrever::Indisponivel => e
    Rails.logger.info("[whatsapp_templates][redacao] unavailable account_id=#{@account.id} reason=#{e.message}")
    indisponivel
  end

  private

  def escrever
    writer = Whatsapp::Templates::Redacao.new(account: @account, timeout: TIMEOUT, max_retries: MAX_RETRIES)
    if @inputs['mode'] == 'create'
      writer.criar(objetivo: @inputs['goal'], tom: @inputs['tone'], tipo: @inputs['category'])
    else
      writer.melhorar(texto: @inputs['text'], melhorias: @inputs['improvements'], tom: @inputs['tone'],
                      tipo: @inputs['category'], recusa: @inputs['meta_reason'])
    end
  end

  def opcao_json(opcao)
    whatsapp = opcao[:whatsapp]
    { text: opcao[:texto], keys: opcao[:chaves_usadas], category: opcao[:categoria_prevista],
      reason: opcao[:motivo_categoria], changes: opcao[:o_que_mudou], name: whatsapp[:nome_sugerido],
      header: whatsapp[:cabecalho], footer: whatsapp[:rodape], buttons: whatsapp[:botoes] }
  end

  def indisponivel
    { error: 'suggestion_unavailable', message: I18n.t('whatsapp_templates.errors.suggestion_unavailable') }
  end
end
