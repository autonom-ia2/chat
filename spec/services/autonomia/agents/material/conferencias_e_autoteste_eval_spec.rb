require 'rails_helper'

# AVALIAÇÃO PAGA DAS CONFERÊNCIAS E DO AUTOTESTE DO MATERIAL (#1426, tema 4b), DESLIGADA POR PADRÃO. Roda só com
# `AUTONOMIA_EVAL_PAGO=1`, `CONFERENCIAS_EVAL=1` e `OPENAI_API_KEY`. Autorizada pelo Rodrigo em 19/10/2026 ("Pode, teto
# US$ 2"): teto TOTAL de US$ 2, somado pelo consumo gravado (Crm::AiUsageEvent); a cena que não cabe no que sobra nem
# começa, e o autoteste recebe como teto só o que sobrou.
# Cenas: C1/C2 foto do cardápio (OCR local de verdade + conferência), C3/C4 planilha sem/com títulos, C5 PDF de texto
# corrido, C6/C7/C8 contradição entre materiais (uma de verdade, duas que não são), A1 autoteste numa base limpa e A2
# autoteste com um material reprovado no meio (o fato some: vira cartão). Opcional: `CONFERENCIAS_EVAL_SAIDA=<arquivo>`
# grava o relatório; `CONFERENCIAS_EVAL_CENA=<nome>` roda só uma cena.
module AvaliacaoDasConferencias
  TETO_USD = 2.0
  # O que cada cena deve custar, no máximo, para começar (o real é gravado no relatório).
  ESTIMATIVA = { conferencia: 0.02, contradicao: 0.08, autoteste: 0.6 }.freeze
  FOTOS = Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao')

  LANCHONETE = 'Você é a Bia, atendente da Lanchonete da Bia. Responda dúvidas de clientes pelo WhatsApp com simpatia e ' \
               'brevidade, usando só o que está no material. O que não estiver no material, diga que vai verificar com a equipe.'.freeze

  CARDAPIO = <<~TXT.freeze
    Cardápio da Lanchonete da Bia
    X-Burguer: pão, hambúrguer de 150 g, queijo e salada. R$ 24,00.
    X-Bacon: pão, hambúrguer de 150 g, queijo e bacon. R$ 28,00.
    Misto quente: pão de forma, presunto e queijo. R$ 12,00.
    Suco natural de laranja (500 ml): R$ 9,00. Refrigerante lata: R$ 6,00.
  TXT

  FUNCIONAMENTO = <<~TXT.freeze
    Horário de funcionamento: de segunda a sexta, das 11h às 22h. Sábado, das 11h às 15h. Domingo fechado.
    Endereço: Rua das Laranjeiras, 120, Centro.
  TXT

  ENTREGA = <<~TXT.freeze
    Entrega: atendemos só o bairro Centro, com taxa fixa de R$ 5,00. Pedido mínimo para entrega: R$ 30,00.
    Pagamento: Pix, cartão de débito e dinheiro. Não aceitamos cartão de crédito.
  TXT

  PLANILHA_SEM_TITULOS = <<~TXT.freeze
    ## Planilha1
    101 | 24 | 3
    102 | 28 | 0
    103 | 12 | 7
    104 | 9 | 12
  TXT

  PLANILHA_COM_TITULOS = <<~TXT.freeze
    ## Preços
    Produto | Preço (R$) | Estoque
    X-Burguer | 24 | 3
    X-Bacon | 28 | 0
    Misto quente | 12 | 7
  TXT

  PDF_CORRIDO = <<~TXT.freeze
    A Lanchonete da Bia nasceu em 2015, quando a Bia começou a vender lanches na porta de casa. Hoje a casa trabalha com
    ingredientes frescos, comprados toda manhã na feira do bairro, e prepara cada lanche na hora. O atendimento é feito
    pela própria família, e a política da casa é simples: se o cliente não gostou, a gente troca o lanche sem custo.
  TXT

  CENAS = [
    { nome: 'C1_foto_legivel', tipo: :conferencia, foto: 'cardapio-legivel.png', espera: { leitura: %w[legivel nao_se_aplica], problema: nil } },
    { nome: 'C2_foto_borrada', tipo: :conferencia, foto: 'cardapio-borrado.png', espera: { leitura: %w[ruim], problema: 'ocr' } },
    { nome: 'C3_planilha_sem_titulos', tipo: :conferencia, source_type: 'xlsx', texto: PLANILHA_SEM_TITULOS,
      espera: { tabela: %w[sem_cabecalho], problema: 'sem_cabecalho' } },
    { nome: 'C4_planilha_com_titulos', tipo: :conferencia, source_type: 'xlsx', texto: PLANILHA_COM_TITULOS,
      espera: { tabela: %w[com_cabecalho], problema: nil } },
    { nome: 'C5_pdf_texto_corrido', tipo: :conferencia, source_type: 'pdf', texto: PDF_CORRIDO,
      espera: { tabela: %w[nao_se_aplica], problema: nil } },
    { nome: 'C6_sabado_diverge', tipo: :contradicao, contradicoes: 1,
      materiais: { 'site' => 'Funcionamos de segunda a sexta das 9h às 18h e no sábado das 9h às 13h.',
                   'folheto.pdf' => 'Horário: segunda a sexta das 9h às 18h; sábado das 9h às 12h.' } },
    { nome: 'C7_complementares', tipo: :contradicao, contradicoes: 0,
      materiais: { 'site' => 'Funcionamos de segunda a sexta das 9h às 18h e no sábado das 9h às 13h.',
                   'entrega.pdf' => 'Entregamos no Centro e na Vila Nova, com taxa de R$ 5,00.' } },
    { nome: 'C8_mesmo_fato_outras_palavras', tipo: :contradicao, contradicoes: 0,
      materiais: { 'site' => 'Aos sábados abrimos às 9h e fechamos às 13h.',
                   'folheto.pdf' => 'Sábado: das 9 da manhã até a 1 da tarde.' } },
    { nome: 'A1_autoteste_base_limpa', tipo: :autoteste },
    { nome: 'A2_autoteste_material_reprovado_no_meio', tipo: :autoteste, reprovar_no_meio: true }
  ].freeze
end

RSpec.describe 'Avaliação paga das conferências e do autoteste do material (#1426)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:relatorio) { [] }
  let(:saidas_da_conferencia) { [] }
  let(:reprovadas) { [] }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def criar_agente(nome = 'Bia')
    Autonomia::Agents::Agent.create!(
      account: conta, name: nome, agent_type: 'support', mode: :guided, status: :active, enabled: true,
      instruction: AvaliacaoDasConferencias::LANCHONETE, tone: 'simpático e breve', greeting: 'Oi! Aqui é a Bia.',
      fallback_message: 'Vou verificar com a equipe e te retorno.', handoff_rule: 'Passe para a equipe o que não souber.',
      human_card: 'A Bia atende os clientes da Lanchonete da Bia.', config: { 'with_knowledge' => true }
    )
  end

  # Material lido e aprovado, um trecho por parágrafo, com o vetor de verdade (o Retriever do autoteste o encontra).
  def material(agent, nome, texto, source_type: 'txt')
    fonte = Autonomia::Agents::Source.create!(account: conta, agent: agent, source_type: source_type, reference: nome,
                                              status: :ready, review_status: 'accepted', reviewed_at: Time.current,
                                              review_summary: texto.lines.first.strip, metadata: {})
    trechos = texto.split("\n").map(&:strip).compact_blank
    vetores = Autonomia::Agents::EmbeddingService.new(account: conta).embed_batch(trechos)
    trechos.zip(vetores).each_with_index do |(trecho, vetor), indice|
      Autonomia::Agents::KnowledgeEntry.create!(account: conta, agent: agent, source: fonte, status: :ready,
                                                chunk_index: indice, content: trecho, embedding: vetor)
    end
    fonte
  end

  def conferencia(cena)
    texto = texto_da_cena(cena)
    saidas_da_conferencia.clear
    veredito = Autonomia::Agents::Material::ConferenciaDoMaterial.new(source: fonte_da_cena(cena), amostra: texto).conferir
    saida = saidas_da_conferencia.last.to_h
    { texto_lido_chars: texto.to_s.strip.size, modelo: saida, veredito: veredito,
      aprovada: conferencia_certa?(cena[:espera], veredito, saida) }
  end

  # A foto passa pelo OCR de verdade (tesseract local, sem custo); o resto já é o texto extraído.
  def texto_da_cena(cena)
    return cena[:texto] unless cena[:foto]

    Autonomia::Agents::Knowledge::Processors::Ocr.ler(AvaliacaoDasConferencias::FOTOS.join(cena[:foto])).force_encoding('UTF-8')
  end

  def fonte_da_cena(cena)
    Autonomia::Agents::Source.create!(account: conta, agent: criar_agente, reference: cena[:foto] || 'material',
                                      source_type: cena[:foto] ? 'foto' : cena[:source_type], status: :ready, metadata: {})
  end

  def conferencia_certa?(espera, veredito, saida)
    return false if veredito.nil? || veredito['problema'] != espera[:problema]

    %i[leitura tabela].all? { |campo| espera[campo].nil? || espera[campo].include?(saida[campo.to_s]) }
  end

  def contradicao(cena)
    agent = criar_agente
    cena[:materiais].each { |nome, texto| material(agent, nome, texto) }
    # conferir! devolve a conferência gravada (ou nil, IA indisponível).
    lista = Autonomia::Agents::Material::Contradicoes.new(agent).conferir!&.dig('contradicoes')
    { contradicoes: lista, aprovada: !lista.nil? && lista.size == cena[:contradicoes] }
  end

  def autoteste(cena)
    agent = criar_agente
    materiais_da_lanchonete(agent)
    reprovar_no_meio if cena[:reprovar_no_meio]
    salvo = rodar_autoteste(agent)
    itens = Array(salvo['itens'])
    cartoes = Autonomia::Agents::Material::Problemas.new(agent).lista.select { |problema| problema['tipo'].start_with?('autoteste') }
    { estado: salvo['estado'], motivo: salvo['motivo'], gasto_da_rodada_usd: salvo['gasto_usd'],
      itens: itens.map { |item| item.slice('origem', 'pergunta', 'esperado', 'fonte', 'resposta', 'equipe', 'veredito') },
      cartoes: cartoes.map { |cartao| cartao.slice('tipo', 'pergunta') }, fonte_reprovada: reprovadas.first&.id,
      aprovada: salvo['estado'] == 'pronto' && autoteste_aprovado?(cena, itens, cartoes) }
  end

  def materiais_da_lanchonete(agent)
    { 'cardapio.txt' => AvaliacaoDasConferencias::CARDAPIO, 'funcionamento.txt' => AvaliacaoDasConferencias::FUNCIONAMENTO,
      'entrega.txt' => AvaliacaoDasConferencias::ENTREGA }.each { |nome, texto| material(agent, nome, texto) }
  end

  # A rodada como o job a roda, com teto = o que sobra do teto total da avaliação.
  def rodar_autoteste(agent)
    estado = Autonomia::Agents::Material::Autoteste.pedir!(agent, quando: 'pedido')
    medidor = Autonomia::Agents::Material::MedidorDeCusto.new(teto: AvaliacaoDasConferencias::TETO_USD - custo_ate_agora)
    Autonomia::Agents::Material::Autoteste.new(agent, estado['rodada'], medidor: medidor).rodar!
    agent.reload.chave_do_material('autoteste').to_h
  end

  # Gera as perguntas com a base inteira e, antes das respostas, reprova o material da 1ª pergunta (como a pessoa que
  # tem um material reprovado pela conferência): as perguntas dele não têm mais resposta.
  def reprovar_no_meio
    allow_any_instance_of(Autonomia::Agents::Material::PerguntasDoAutoteste).to receive(:gerar).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
      original.call.tap do |geradas|
        fonte = Autonomia::Agents::Source.find_by(id: geradas&.dig(:material, 0, 'fonte'))
        fonte&.update!(review_status: 'needs_resend')
        reprovadas << fonte if fonte
      end
    end
  end

  # Até 10 (no máximo 8 do material), as 2 de fora recusadas. Base limpa: todas certas e nenhum cartão. Com o material
  # reprovado: as perguntas dele erradas, e cada uma vira cartão.
  def autoteste_aprovado?(cena, itens, cartoes)
    do_material = itens.select { |item| item['origem'] == 'material' }
    return false unless formato_certo?(itens, do_material)
    return base_limpa_certa?(do_material, cartoes) unless cena[:reprovar_no_meio]

    reprovado_vira_cartao?(do_material.select { |item| item['fonte'] == reprovadas.first&.id }, cartoes)
  end

  def reprovado_vira_cartao?(sem_material, cartoes)
    sem_material.any? && sem_material.all? { |item| item['veredito'] == 'errado' } && cartoes.size >= sem_material.size
  end

  def formato_certo?(itens, do_material)
    de_fora = itens - do_material
    itens.size.between?(3, 10) && do_material.size <= 8 && de_fora.size == 2 && de_fora.all? { |item| item['veredito'] == 'recusou' }
  end

  def base_limpa_certa?(do_material, cartoes)
    do_material.all? { |item| item['veredito'] == 'certo' } && cartoes.empty?
  end

  def rodar(cena)
    inicio = custo_ate_agora
    resultado = send(cena[:tipo], cena)
    { cena: cena[:nome], **resultado, custo_da_cena_usd: (custo_ate_agora - inicio).round(4), custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def cenas_escolhidas
    nome = ENV.fetch('CONFERENCIAS_EVAL_CENA', nil).presence
    escolhidas = nome ? AvaliacaoDasConferencias::CENAS.select { |cena| cena[:nome] == nome } : AvaliacaoDasConferencias::CENAS
    expect(escolhidas).not_to be_empty, "cena desconhecida: #{nome}"
    escolhidas
  end

  def cabe?(cena)
    custo_ate_agora + AvaliacaoDasConferencias::ESTIMATIVA.fetch(cena[:tipo]) <= AvaliacaoDasConferencias::TETO_USD
  end

  it 'confere leitura, tabela e contradição pelo sentido, e o autoteste acha o que falta sem inventar' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['CONFERENCIAS_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, CONFERENCIAS_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    allow_any_instance_of(Autonomia::Agents::Material::ConferenciaDoMaterial).to receive(:veredito).and_wrap_original do |original, saida| # rubocop:disable RSpec/AnyInstance
      saidas_da_conferencia << saida
      original.call(saida)
    end

    cenas_escolhidas.each do |cena|
      break unless cabe?(cena)

      relatorio << rodar(cena)
    end

    destino = ENV.fetch('CONFERENCIAS_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(custo_usd: custo_ate_agora.round(4), execucoes: relatorio)) if destino.present?
    expect(custo_ate_agora).to be <= AvaliacaoDasConferencias::TETO_USD
    expect(relatorio.size).to eq(cenas_escolhidas.size), "teto de custo atingido: #{relatorio.size} de #{cenas_escolhidas.size}"
    expect(relatorio.reject { |linha| linha[:aprovada] }.pluck(:cena)).to eq([])
  end
end
