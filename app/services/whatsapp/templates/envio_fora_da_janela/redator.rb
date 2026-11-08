# A IA escreve o modelo de um tipo para o negócio (#1587): o redator compartilhado (`Ai::Redacao::Escrever`, canal
# `whatsapp_modelo`, #1333) com o propósito do tipo e a regra de categoria dele no `pedido`. O prompt da tela de Modelos
# não muda: a regra vale só neste caminho. Entra só o propósito, o nome da conta e os funis da caixa (dado), nunca dado
# de cliente.
#
#   Redator.new(inbox:, tipo:).escrever(recusa: 'INCORRECT_CATEGORY')
#   # => ['Olá, {{1}}! ...', { '1' => 'cliente.primeiro_nome', ... }] | 'ia_indisponivel' | 'ia_sem_opcao'
#
# Serve a primeira opção só de corpo (sem botões nem cabeçalho; o rodapé fica de fora) e, para utilidade, que a IA prevê
# como serviço. A categoria prevista é só previsão: quem decide é a Meta, e a regra de uso relê a categoria aprovada.
class Whatsapp::Templates::EnvioForaDaJanela::Redator
  Tipos = Whatsapp::Templates::EnvioForaDaJanela::Tipos
  FEATURE = 'modelo_fora_da_janela'.freeze
  PROPOSITO = 'criar um modelo de mensagem do WhatsApp'.freeze
  SO_CORPO = 'Escreva só o corpo: sem botões, sem cabeçalho e sem rodapé.'.freeze
  # A regra de categoria pelo propósito (pesquisa oficial no #1585), só neste caminho.
  REGRA_DA_CATEGORIA = {
    Tipos::UTILITY => 'É aviso de serviço ("servico"): fale do pedido específico do cliente, diga em que pé está e o próximo ' \
                      'passo. Sem oferta, desconto, urgência, "aproveite" nem convite para comprar.',
    Tipos::MARKETING => 'É divulgação ("divulgacao") sempre, mesmo que o cliente tenha pedido o contato: não redija para ' \
                        'parecer aviso de serviço.'
  }.freeze
  TOM = 'simpatico'.freeze
  OPCOES = 3
  MAX_CHARS = 350
  # O redator roda num job: mais tempo e uma nova tentativa, como a tela de Modelos (`Sugestao`).
  TIMEOUT = 25
  MAX_RETRIES = 1
  CATEGORIA_PREVISTA = { Tipos::UTILITY => 'servico', Tipos::MARKETING => 'divulgacao' }.freeze
  MAX_FUNIS = 5
  MAX_QUANDO_USAR = 200

  def initialize(inbox:, tipo:)
    @inbox = inbox
    @tipo = tipo
  end

  def escrever(recusa: nil)
    opcao = Ai::Redacao::Escrever.call(
      account: @inbox.account, feature: FEATURE, canal: 'whatsapp_modelo', proposito: PROPOSITO, pedido: pedido,
      tom: TOM, opcoes: OPCOES, chaves: { permitidas: @tipo.campos, obrigatorias: @tipo.obrigatorios },
      limites: { max_chars: MAX_CHARS, categoria_desejada: CATEGORIA_PREVISTA[@tipo.categoria], sem_midia: true },
      contexto: contexto(recusa), timeout: TIMEOUT, max_retries: MAX_RETRIES
    )[:opcoes].find { |item| serve?(item) }
    opcao ? numerar(opcao[:texto]) : 'ia_sem_opcao'
  rescue Ai::Redacao::Escrever::Indisponivel
    'ia_indisponivel'
  end

  private

  # #2034: a linha de vocabulário da conta fecha o pedido; conta fora de um pacote não recebe nada a mais.
  def pedido
    [@tipo.proposito, REGRA_DA_CATEGORIA.fetch(@tipo.categoria), SO_CORPO, Crm::Ai::Vocabulario.da(@inbox.account)]
      .compact_blank.join(' ')
  end

  def serve?(opcao)
    whatsapp = opcao[:whatsapp].to_h
    return false unless whatsapp[:botoes].blank? && whatsapp[:cabecalho].blank?

    @tipo.propaganda? || opcao[:categoria_prevista] == CATEGORIA_PREVISTA[Tipos::UTILITY]
  end

  # O negócio, como dado: o nome da conta e os funis ligados à caixa (com o "quando usar" que a equipe escreveu).
  def contexto(recusa)
    { empresa: @inbox.account.name, funis: funis, recusa_anterior: recusa }.compact
  end

  def funis
    @inbox.account.crm_pipelines.active.joins(:pipeline_inboxes).where(crm_pipeline_inboxes: { inbox_id: @inbox.id })
          .order(:position, :id).limit(MAX_FUNIS)
          .map { |funil| { nome: funil.name, quando_usar: funil.when_to_use.to_s.squish.first(MAX_QUANDO_USAR).presence }.compact }
  end

  # "Oi, {{cliente.primeiro_nome}}!" -> ["Oi, {{1}}!", { "1" => "cliente.primeiro_nome" }], na ordem do texto.
  def numerar(texto)
    campos = {}
    corpo = Ai::Redacao::Chaves.partes(texto).map do |parte|
      next parte.valor unless parte.chave?

      posicao = (campos.size + 1).to_s
      campos[posicao] = parte.valor
      "{{#{posicao}}}"
    end
    [corpo.join, campos]
  end
end
