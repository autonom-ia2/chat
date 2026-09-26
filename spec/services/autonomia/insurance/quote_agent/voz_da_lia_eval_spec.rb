require 'rails_helper'

# AVALIAÇÃO PAGA DA VOZ DA LIA, DESLIGADA POR PADRÃO (itens 9, 6 e 5A, 26/09/2026). Roda só com `AUTONOMIA_EVAL_PAGO=1`
# e `OPENAI_API_KEY`, contra o modelo de produção da Lia e do especialista; o portal é o dublê (`Connector::Mock`), e
# nada sai para o AGGER. Opcional: `VOZ_DA_LIA_EVAL_SAIDA=<arquivo>` grava o relatório (falas, vereditos e o que o
# especialista devolveu à Lia) para leitura.
#
# DUAS CENAS, a mesma conversa de cliente que a auditoria mostrou:
#   A. três avisos de fim de cotação seguidos, de três bens pedidos na mesma mensagem (itens 6 e 5A);
#   B. um turno em que a pessoa conta contexto e pede o que não cabe, e a Lia chama o especialista de verdade (item 9).
#
# CRITÉRIOS (todos obrigatórios, nenhum passa por tempo esgotado):
#   - o `item` (identificador nosso) literal em 0% das falas;
#   - nos três avisos seguidos, pelo menos 2 aberturas diferentes (as duas primeiras palavras: com três, "o comparativo
#     do" e "o comparativo da" contavam como diferentes, e era a mesma forma);
#   - um juiz de OUTRO modelo (`JUIZ`) decide, em cada fala, se ela reagiu ao que a pessoa disse e se chamou o bem
#     como a pessoa chama;
#   - as guardas: nenhum travessão; nenhum valor em reais além dos que a pessoa ou os fatos deram (nenhuma cena tem
#     preço lido, então qualquer outro valor é preço inventado); e o juiz não vê fala de recusa nem de seguradora que
#     ficou sem proposta. O valor de cobertura que a pessoa pediu ("vendaval de 300 mil") não é preço, e pode voltar.
#
# A spec só usa o que já existia antes desta PR (`Builder`, `Answerer`, `Tools::Evento`, `ToolRun`), para medir o
# ANTES com ela mesma, sobre a `main`.
module AvaliacaoDaVozDaLia
  JUIZ = 'gpt-5.4'.freeze

  PEDIDO = 'Oi! Quero fazer o seguro do meu apê na praia, da casa onde a gente mora em Campinas e do Onix da minha ' \
           'esposa. O do apê vence sexta, então ele é o mais urgente. No apê eu queria danos elétricos, que lá cai ' \
           'muito raio, e na casa quero vendaval de 300 mil.'.freeze
  RESPOSTA_DA_LIA = 'Já comecei os três. O do apê eu priorizo por causa da sexta.'.freeze
  COMO_A_PESSOA_CHAMA = { 'apto 302 bloco b' => 'o apê na praia', 'casa rua 7 120' => 'a casa onde mora, em Campinas',
                          'onix qwe1a23' => 'o Onix da esposa' }.freeze
  BENS = [
    { item: 'apto 302 bloco b', produto: 'residencial', entrou: 'danos elétricos de 20 mil', nao_coube: nil },
    { item: 'casa rua 7 120', produto: 'residencial', entrou: nil,
      nao_coube: 'vendaval de 300 mil: esta cobertura vai até 100 mil, e a cotação saiu com 100 mil' },
    { item: 'onix qwe1a23', produto: 'auto', entrou: nil, nao_coube: nil }
  ].freeze

  CONTEXTO = 'Quero cotar o seguro do carro da minha filha. Ela tirou a carta mês passado e começa a ir de carro pra ' \
             'faculdade na segunda, então tô com pressa. Placa TYV8I74, CEP 31110-210, meu CPF 529.982.247-25. ' \
             'Queria carro reserva de 20 dias.'.freeze

  VEREDITO = {
    name: 'veredito_da_fala',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[chamou_o_bem_como_a_pessoa reagiu_ao_que_a_pessoa_disse devolve_com_pergunta_de_verdade
                   fala_de_recusa_ou_de_quem_ficou_sem_proposta justificativa],
      properties: {
        chamou_o_bem_como_a_pessoa: {
          type: 'boolean',
          description: 'A mensagem chama o bem pelo nome que a pessoa usa, ou por um equivalente natural, e nunca por ' \
                       'código, placa, número de endereço ou identificador interno? Se não cita bem nenhum, responda sim.'
        },
        reagiu_ao_que_a_pessoa_disse: {
          type: 'boolean',
          description: 'Pelo conteúdo, a mensagem leva em conta algo que a pessoa contou (pressa, para quem é, ' \
                       'preocupação, um pedido dela), em vez de ser uma frase que serviria a qualquer cliente?'
        },
        devolve_com_pergunta_de_verdade: { type: 'boolean', description: 'A mensagem devolve a conversa com uma pergunta real, ' \
                                                                         'e não com instrução de como abrir ou usar um arquivo?' },
        fala_de_recusa_ou_de_quem_ficou_sem_proposta: { type: 'boolean', description: 'A mensagem fala de recusa, de risco ' \
                                                                                      'não aceito, ou de seguradora que ficou sem proposta?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia uma mensagem que uma atendente de corretora de seguros mandou a um cliente no ' \
                      'WhatsApp. Você recebe o que o cliente escreveu, como ele chama cada bem, e a mensagem. Responda ' \
                      'cada campo pelo sentido, sem ser generoso.'.freeze

  # Os valores em reais que a pessoa ou os fatos deram, em centavos, como `ConferenciaDePrecos.valores` os lê: "R$ 300
  # mil" lido como 300, e por extenso como 300.000.
  VALORES_DADOS = [20, 100, 300].flat_map { |mil| [mil * 100, mil * 1000 * 100] }.freeze

  module_function

  # -> os valores em reais da fala que ninguém deu.
  def valores_inventados(fala)
    Autonomia::Agents::ConferenciaDePrecos.valores(fala) - VALORES_DADOS
  end

  def abertura(fala)
    ActiveSupport::Inflector.transliterate(fala.to_s).downcase.tr('^a-z0-9 ', ' ').split.first(2).join(' ')
  end

  def travessao?(fala)
    fala.include?('—') || fala.include?('–')
  end
end

RSpec.describe 'A voz da Lia, avaliação paga' do # rubocop:disable RSpec/DescribeClass
  let(:builder) { Autonomia::Insurance::QuoteAgent::Builder }
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:relatorio) { { falas: [], vereditos: [], do_especialista: [] } }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def lia
    @lia ||= builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Seguros do Vale').call
  end

  def conexao_pronta
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
  end

  def mensagem(tipo, texto, atributos = {})
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: tipo, content: texto,
                     content_attributes: atributos)
  end

  def historico
    conversation.messages.reload.where(private: false).order(:created_at, :id)
                .map { |m| { role: m.incoming? ? 'user' : 'assistant', content: m.content.to_s } }
  end

  def responder(query, delivery)
    Autonomia::Agents::Answerer.new(agent: lia, query: query, history: historico, trust_instruction: true, delivery: delivery,
                                    **builder.rodadas_do_turno(lia)).answer.reply.to_s
  end

  def execucao(bem, origem)
    Autonomia::Agents::ToolRun.create!(
      account: account, agent: lia, slug: 'cotar_seguro', status: 'running', faixa: "#{bem[:produto]}:#{bem[:item]}",
      conversation_id: conversation.id, origin_message_id: origem.id, execution_key: SecureRandom.uuid,
      arguments: { 'produto' => bem[:produto], 'item' => bem[:item], 'pedido_que_entrou' => bem[:entrou],
                   'pedido_que_nao_coube' => bem[:nao_coube] }.compact,
      handle: { Autonomia::Agents::Tools::Native::InsuranceQuote::DELIVERED_KEY => %w[1 2 3 4] }
    )
  end

  # Como em produção: a cotação termina, o fecho é adquirido, e só então vem o aviso dela.
  def terminar(run)
    run.update!(status: 'done', handle: run.handle.merge(Autonomia::Agents::Tools::Evento::FECHO_KEY => 'concluida'))
  end

  def julgar(cliente, fala, pedido)
    texto = "O cliente escreveu: #{pedido}\nComo o cliente chama cada bem: #{AvaliacaoDaVozDaLia::COMO_A_PESSOA_CHAMA.values.join('; ')}; " \
            "o carro da filha.\nA mensagem da atendente: #{fala}"
    raw = cliente.create(model: AvaliacaoDaVozDaLia::JUIZ, instructions: AvaliacaoDaVozDaLia::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)], schema: AvaliacaoDaVozDaLia::VEREDITO)
    JSON.parse(raw[:text])
  end

  # A: os três avisos de fim de cotação, um depois do outro: as três correm juntas, e cada uma termina logo antes do
  # aviso dela, com as anteriores já contadas.
  def cena_dos_tres_avisos
    origem = mensagem(:incoming, AvaliacaoDaVozDaLia::PEDIDO)
    mensagem(:outgoing, AvaliacaoDaVozDaLia::RESPOSTA_DA_LIA)
    execucoes = AvaliacaoDaVozDaLia::BENS.map { |bem| execucao(bem, origem) }
    execucoes.map do |run|
      terminar(run)
      evento = Autonomia::Agents::Tools::Evento.new(run: run, tipo: 'concluida')
      delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, evento: 'concluida',
                                                        execucao_do_evento: run)
      fala = responder(evento.nota_do_sistema, delivery)
      mensagem(:outgoing, fala, Autonomia::Agents::Tools::Evento::CHAVE => evento.marca)
      { cena: 'A', item: run.arguments['item'], fala: fala }
    end
  end

  # B: a pessoa conta para quem é, a pressa, e pede o que não cabe; a Lia chama o especialista de verdade.
  def cena_do_contexto
    conexao_pronta
    origem = mensagem(:incoming, AvaliacaoDaVozDaLia::CONTEXTO)
    delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: origem.id)
    fala = responder(AvaliacaoDaVozDaLia::CONTEXTO, delivery)
    itens = Autonomia::Agents::ToolRun.where(conversation_id: conversation.id, origin_message_id: origem.id)
                                      .filter_map { |run| run.arguments['item'].presence }
    [{ cena: 'B', item: itens.first, fala: fala }]
  end

  def gravar_relatorio
    destino = ENV.fetch('VOZ_DA_LIA_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(relatorio)) if destino.present?
  end

  it 'a Lia fala como gente nos avisos e depois do especialista', :eval_pago do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    # O que o especialista devolveu à Lia, para o relatório: o formato especialista -> principal, medido.
    allow_any_instance_of(Autonomia::Agents::Specialists::Runner).to receive(:call).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      original.call(*args).tap { |saida| relatorio[:do_especialista] << saida }
    end

    avisos = cena_dos_tres_avisos
    contexto = cena_do_contexto
    relatorio[:falas] = avisos + contexto
    juiz = Crm::Ai::ResponsesClient.new(credential: { api_key: ENV.fetch('OPENAI_API_KEY') }, feature: 'eval_voz_da_lia')
    relatorio[:vereditos] = relatorio[:falas].map do |caso|
      julgar(juiz, caso[:fala], caso[:cena] == 'A' ? AvaliacaoDaVozDaLia::PEDIDO : AvaliacaoDaVozDaLia::CONTEXTO)
    end
    aberturas = avisos.map { |caso| AvaliacaoDaVozDaLia.abertura(caso[:fala]) }
    relatorio[:aberturas] = aberturas
    gravar_relatorio

    falas = relatorio[:falas]
    expect(falas.map { |caso| caso[:fala] }).to all(be_present)
    expect(falas.select { |caso| caso[:item].present? && caso[:fala].downcase.include?(caso[:item].downcase) }).to be_empty
    expect(aberturas.uniq.size).to be >= 2
    expect(falas.select { |caso| AvaliacaoDaVozDaLia.travessao?(caso[:fala]) || AvaliacaoDaVozDaLia.valores_inventados(caso[:fala]).any? })
      .to be_empty
    expect(relatorio[:vereditos].pluck('chamou_o_bem_como_a_pessoa')).to all(be(true))
    expect(relatorio[:vereditos].pluck('reagiu_ao_que_a_pessoa_disse')).to all(be(true))
    expect(relatorio[:vereditos].pluck('fala_de_recusa_ou_de_quem_ficou_sem_proposta')).to all(be(false))
  end
end
