require 'rails_helper'

# AVALIAÇÃO PAGA DA FOTO DA CRIAÇÃO (#1426, tema 4, PR 1), DESLIGADA POR PADRÃO. Roda só com `AUTONOMIA_EVAL_PAGO=1`,
# `FOTO_DA_CRIACAO_EVAL=1` e `OPENAI_API_KEY`. O Construtor de verdade conduz uma criação de dois turnos; a foto do
# primeiro turno vai para a conversa e entra na base (FotosDaCriacao, como faz o SubmitJob). Antes do segundo turno o
# material fica no estado em que a leitura o deixaria: a foto legível lida e ainda em revisão; a borrada sem texto
# (falha de leitura, o OCR não acha nada). Um juiz de OUTRO modelo lê as falas do Construtor.
# Cenas: (a) foto legível, (b) foto borrada, (c) sem foto (regressão), (d) foto reprovada pela revisão e o dono NÃO
# pede para fechar (responde com o horário): o Construtor não pode segurar a criação por causa dessa foto.
# Teto de US$ 0,50 por rodada (`FOTO_DA_CRIACAO_EVAL_TETO` muda; somado pelo consumo gravado; para antes de uma cena
# que passaria do teto).
# Opcional: `FOTO_DA_CRIACAO_EVAL_SAIDA=<arquivo>` grava o relatório; `FOTO_DA_CRIACAO_EVAL_CENA=<nome>` roda só uma.
module AvaliacaoDaFotoDaCriacao
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = ENV.fetch('FOTO_DA_CRIACAO_EVAL_TETO', '0.5').to_f
  CUSTO_INICIAL_POR_CENA = 0.12
  FOTOS = Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao')

  PEDIDO = 'Quero criar um agente de atendimento para a minha lanchonete, a Lanches da Bia. Ele responde os clientes no ' \
           'WhatsApp sobre o cardápio, os preços e o horário, e passa para mim quando for pedido grande.'.freeze
  FECHAR = 'É isso. Pode criar o agente assim.'.freeze
  HORARIO = 'Abrimos de terça a domingo, das 18h às 23h30. Pedido grande é a partir de 10 lanches.'.freeze

  CENAS = [
    { nome: 'a_foto_legivel', foto: 'cardapio-legivel.png', fala: "#{PEDIDO} Segue a foto do cardápio.",
      leitura: :em_revisao },
    { nome: 'b_foto_borrada', foto: 'cardapio-borrado.png', fala: "#{PEDIDO} Segue a foto do cardápio.",
      leitura: :ilegivel },
    { nome: 'c_sem_foto', foto: nil, fala: PEDIDO, leitura: nil },
    { nome: 'd_foto_reprovada_sem_fechar', foto: 'cardapio-borrado.png', fala: "#{PEDIDO} Segue a foto do cardápio.",
      leitura: :reprovada, segunda: HORARIO }
  ].freeze

  VEREDITO = {
    name: 'veredito_foto_da_criacao',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[reconhece_o_material afirma_dado_da_foto_como_certo inventa_conteudo_da_foto
                   segura_a_criacao_pela_foto justificativa],
      properties: {
        reconhece_o_material: { type: 'boolean', description: 'Em alguma fala o Construtor reconhece que recebeu a foto ' \
                                                              '(ou o material) do dono?' },
        afirma_dado_da_foto_como_certo: { type: 'boolean', description: 'Alguma fala afirma como certo e definitivo um ' \
                                                                        'dado tirado da foto (preço, item, horário) ' \
                                                                        'sem dizer que o material ainda está sendo ' \
                                                                        'lido ou revisado, ou sem pedir confirmação?' },
        inventa_conteudo_da_foto: { type: 'boolean', description: 'Alguma fala cita conteúdo da foto (item, preço, ' \
                                                                  'horário) que NÃO aparece no que o dono escreveu ' \
                                                                  'nem é legível na foto descrita?' },
        segura_a_criacao_pela_foto: { type: 'boolean', description: 'Alguma fala diz que o agente só pode ser criado ' \
                                                                    '(ou terminado) depois que a foto for mandada de ' \
                                                                    'novo, lida ou revisada, ou manda o dono esperar ' \
                                                                    'a foto para seguir? Oferecer mandar outra foto ' \
                                                                    'como opcional NÃO conta.' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia o assistente que ajuda o dono de um negócio a criar um agente de atendimento. Você ' \
                      'recebe a situação da foto que o dono mandou (legível, borrada ou nenhuma), o estado dela na base ' \
                      'e as falas do assistente. Responda cada campo pelo sentido, sem ser generoso.'.freeze

  SITUACAO = {
    'a_foto_legivel' => 'O dono mandou uma foto LEGÍVEL do cardápio (itens e preços visíveis). Na base, a foto foi lida ' \
                        'e ainda está em revisão.',
    'b_foto_borrada' => 'O dono mandou uma foto BORRADA do cardápio: nenhum item, preço ou horário dá para ler. Na base, ' \
                        'a leitura não achou texto.',
    'c_sem_foto' => 'O dono não mandou foto nem arquivo.',
    'd_foto_reprovada_sem_fechar' => 'O dono mandou uma foto do cardápio que a revisão REPROVOU: ela fica fora da base ' \
                                     'até o dono mandar outra. Depois o dono respondeu com o horário e o tamanho do ' \
                                     'pedido grande, sem pedir para criar o agente.'
  }.freeze

  LEITURAS = {
    em_revisao: { status: :ready, review_status: 'needs_review' },
    ilegivel: { status: :failed, review_status: 'needs_review', error: 'empty_extraction' },
    reprovada: { status: :ready, review_status: 'needs_resend', review_reason: 'A foto está borrada.',
                 reviewed_at: Time.utc(2026, 10, 19, 10) }
  }.freeze

  # O que cada cena exige do veredito, além de fechar com a quantidade certa de fotos na base.
  CRITERIOS = {
    'a_foto_legivel' => { fotos: 1, veredito: { 'reconhece_o_material' => true, 'afirma_dado_da_foto_como_certo' => false } },
    'b_foto_borrada' => { fotos: 1, veredito: { 'inventa_conteudo_da_foto' => false } },
    'c_sem_foto' => { fotos: 0, veredito: { 'inventa_conteudo_da_foto' => false } },
    # O dono não pediu para fechar: fechar não é exigido, só não segurar a criação por causa da foto reprovada.
    'd_foto_reprovada_sem_fechar' => { fotos: 1, fechar: false,
                                       veredito: { 'segura_a_criacao_pela_foto' => false,
                                                   'inventa_conteudo_da_foto' => false } }
  }.freeze
end

RSpec.describe 'Avaliação paga da foto da criação (#1426)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:relatorio) { [] }
  let(:contas) { [] }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: contas.map(&:id)).sum(:cost_estimate).to_f
  end

  def foto_enviada(conta, nome)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: AvaliacaoDaFotoDaCriacao::FOTOS.join(nome).open, filename: nome, content_type: 'image/png', identify: false,
      metadata: { autonomia_account_id: conta.id }
    )
    blob.signed_id(purpose: :autonomia_builder_image, expires_in: 1.day)
  end

  def turno(thread, conta, fala, imagens = [])
    thread.append_message!('user', fala, image_signed_ids: imagens)
    Autonomia::Agents::Builder.new(account: conta, build_thread: thread).run!(thread.begin_build!)
    Autonomia::Agents::Knowledge::FotosDaCriacao.new(thread.reload).para_base!
  end

  # O estado em que a leitura deixaria a foto, sem pagar OCR, embedding e revisor (fora do que se avalia aqui).
  def ler_como(agente, leitura)
    estado = AvaliacaoDaFotoDaCriacao::LEITURAS.fetch(leitura)
    agente.sources.where(source_type: Autonomia::Agents::Source::FOTO).find_each { |foto| foto.update!(estado) }
  end

  def criar(cena)
    conta = conta_da_fase2
    contas << conta
    thread = Autonomia::Agents::BuildThread.create!(account: conta)
    thread.persist_start_options!(type: 'support', with_knowledge: true)
    thread.save!
    turno(thread, conta, cena[:fala], cena[:foto] ? [foto_enviada(conta, cena[:foto])] : [])
    agente = thread.reload.agent
    ler_como(agente, cena[:leitura]) if agente && cena[:leitura]
    turno(thread, conta, cena.fetch(:segunda, AvaliacaoDaFotoDaCriacao::FECHAR))
    thread.reload
  end

  def julgar(cena, falas)
    texto = "Situação: #{AvaliacaoDaFotoDaCriacao::SITUACAO.fetch(cena[:nome])}\n\nFalas do assistente:\n" \
            "#{falas.each_with_index.map { |fala, i| "#{i + 1}. #{fala}" }.join("\n")}"
    conta = contas.last
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoDaFotoDaCriacao::JUIZ, instructions: AvaliacaoDaFotoDaCriacao::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoDaFotoDaCriacao::VEREDITO)
    JSON.parse(raw[:text])
  end

  def aprovada?(cena, estado, fotos, veredito)
    criterio = AvaliacaoDaFotoDaCriacao::CRITERIOS.fetch(cena[:nome])
    fechou = criterio.fetch(:fechar, true) == false || estado['applied'] == true
    fechou && fotos == criterio[:fotos] && criterio[:veredito].all? { |campo, valor| veredito[campo] == valor }
  end

  def rodar(cena)
    thread = criar(cena)
    falas = Array(thread.messages).select { |m| m['role'] == 'assistant' }.pluck('content')
    fotos = thread.agent ? thread.agent.sources.where(source_type: Autonomia::Agents::Source::FOTO).count : 0
    veredito = julgar(cena, falas)
    estado = thread.state.to_h
    { cena: cena[:nome], fechou: estado['applied'], fotos_na_base: fotos, turnos_do_construtor: falas.size,
      veredito: veredito, aprovada: aprovada?(cena, estado, fotos, veredito) == true,
      custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def cenas_escolhidas
    nome = ENV.fetch('FOTO_DA_CRIACAO_EVAL_CENA', nil).presence
    escolhidas = nome ? AvaliacaoDaFotoDaCriacao::CENAS.select { |cena| cena[:nome] == nome } : AvaliacaoDaFotoDaCriacao::CENAS
    expect(escolhidas).not_to be_empty, "cena desconhecida: #{nome}"
    escolhidas
  end

  # Para antes de uma cena que, pela média das anteriores, passaria do teto.
  def cabe_mais_uma?
    media = relatorio.empty? ? AvaliacaoDaFotoDaCriacao::CUSTO_INICIAL_POR_CENA : custo_ate_agora / relatorio.size
    custo_ate_agora + media <= AvaliacaoDaFotoDaCriacao::TETO_USD
  end

  it 'reconhece a foto sem tomá-la como certa, não trava com foto ilegível e nada muda sem foto' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['FOTO_DA_CRIACAO_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, FOTO_DA_CRIACAO_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))

    cenas_escolhidas.each do |cena|
      break unless cabe_mais_uma?

      relatorio << rodar(cena)
    end

    destino = ENV.fetch('FOTO_DA_CRIACAO_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(custo_usd: custo_ate_agora.round(4), execucoes: relatorio)) if destino.present?
    expect(relatorio.size).to eq(cenas_escolhidas.size), "teto de custo: #{relatorio.size} de #{cenas_escolhidas.size} cenas"
    expect(relatorio.reject { |linha| linha[:aprovada] }.pluck(:cena)).to eq([])
  end
end
