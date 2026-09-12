require 'rails_helper'

# A PROPOSTA DE UMA SEGURADORA SÓ (entrega 8 do Agente de Cotação, #396 — termos 1, 3 e 4) e a rodada
# de correção de 12/09/2026 (Codex P1/P2 ×3, verificador cego A/B1/B2, mutações M1/M2/M8).
#
# O que estes exemplos travam: o cliente pede a proposta de UMA seguradora e recebe a DAQUELA, não o
# comparativo (termo 1); quem não cotou é dito, com a lista de quem cotou, em vez do comparativo em
# silêncio (termo 3); duas seguradoras são dois arquivos na mesma execução, e NENHUMA cotação nova
# (termo 4 — `quote_start` nunca é chamado daqui). O casamento do nome é comparação de texto contra o
# mapa que a cotação gravou (`nomes_entregues`): o EXATO vence; sem exato, o prefixo de um só nome
# casa; prefixo de mais de um é ambíguo e pergunta; semelhança não existe ("Portu" não é "Porto").
#
# A COTAÇÃO DE ORIGEM É FIXADA NO ACEITE (`#argumentos`) e só ela é usada depois: supersedida entre o
# aceite e o `start`, ou entre o `start` e o `poll`, a resposta é nomeada e nada sai do portal.
# UMA CHAMADA AO PORTAL POR PASSADA e UM ARQUIVO POR PASSADA: é o que mantém cada passada do job
# dentro de uma chamada de 60 s ou de um download de 20 s, e o que faz uma URL gerada estar no banco
# antes de a próxima ser pedida.
#
# Os nomes são os REAIS do portal em 11/09/2026: 8 "Porto", 48 "Bp", 55 "Bp Assinatura", 20 "Suhai".
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceProposal do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true, 'autonomia_agents_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let!(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:nomes) { { '8' => 'Porto', '48' => 'Bp', '55' => 'Bp Assinatura', '20' => 'Suhai' } }
  # O conector é um dublê ESTRITO: qualquer chamada fora de `quote_proposal` (um `quote_start`, um
  # `open_session`) levanta — é assim que "não cota de novo" e "não abre login" ficam provados.
  let(:connector) { instance_double(Autonomia::Insurance::Connector::Mock) }
  # Os códigos pedidos ao portal, na ordem.
  let(:pedidos) { [] }
  let(:conexao) { Autonomia::Insurance::Connection.for_account(account).sole }

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(connector).to receive(:quote_proposal) do |**kwargs|
      pedidos << kwargs[:insurer_code]
      { 'quote_id' => kwargs[:quote_id], 'url' => "https://arquivos.exemplo.test/proposta-#{kwargs[:insurer_code]}.pdf" }
    end
    allow(connector).to receive(:quote_start)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  # A cotação que a proposta lê: com preço entregue e o mapa código -> nome (entrega 8), como a
  # ferramenta de cotação a deixa. `done` por padrão; `running` é a lista parcial que o cliente lê.
  def cotacao_com_precos(mapa: nomes, conversa: conversation, quote_id: 'q1', status: 'done',
                         arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'abc-1d23' } })
    Autonomia::Agents::ToolRun.create!(
      account: account, agent: agent, conversation_id: conversa.id, slug: cotacao.slug, status: status,
      execution_key: SecureRandom.uuid, arguments: arguments,
      handle: { 'quote_id' => quote_id, 'produto' => arguments['produto'], cotacao::DELIVERED_KEY => mapa.keys,
                cotacao::NOMES_KEY => mapa }
    )
  end

  # Uma cotação NOVA aberta pelo caminho real (`open!`): supersede a viva anterior e ainda não tem preço.
  def cotacao_nova_em_andamento
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, arguments: { 'produto' => 'auto' },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run
  end

  def arquivo(entrega)
    Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega)
  end

  # No TURNO ela nasce com o `delivery` (`Bound#accept_async`) e ESCOLHE a origem.
  def no_turno(*seguradoras)
    described_class.new(agent: agent, params: { 'seguradoras' => seguradoras }, delivery: delivery)
  end

  # No JOB ela nasce sem `delivery`, com os argumentos que o ACEITE gravou (`#argumentos`, a origem
  # fixada), a conversa e a LINHA da execução (`AsyncRunJob#ferramenta`). É o caminho real
  # aceite -> job. A linha só é necessária a partir do `poll`: é dela que sai o token pelo qual a
  # ferramenta pergunta o que já virou mensagem.
  def no_job(*seguradoras, run: nil)
    described_class.new(agent: agent, params: no_turno(*seguradoras).argumentos, conversation: conversation, run: run)
  end

  # No job, com a origem ESCRITA À MÃO: para provar que o `start` usa só ela.
  def no_job_com_origem(origem, *seguradoras, run: nil)
    params = { 'seguradoras' => seguradoras, described_class::ORIGEM => origem&.id }
    described_class.new(agent: agent, params: params, conversation: conversation, run: run)
  end

  # A EXECUÇÃO como o ACEITE a abre: com os argumentos da ferramenta (a origem fixada dentro),
  # promovida, que é o estado em que o job a encontra.
  def execucao(*seguradoras, argumentos: nil)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug,
                                           arguments: argumentos || no_turno(*seguradoras).argumentos,
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run
  end

  def portal_que_recusa(*codigos)
    allow(connector).to receive(:quote_proposal) do |**kwargs|
      raise Autonomia::Insurance::Connector::Error.new(:validation, 'nao cotou') if codigos.include?(kwargs[:insurer_code])

      pedidos << kwargs[:insurer_code]
      { 'quote_id' => kwargs[:quote_id], 'url' => "https://arquivos.exemplo.test/proposta-#{kwargs[:insurer_code]}.pdf" }
    end
  end

  def portal_fora_do_ar_para(*codigos)
    allow(connector).to receive(:quote_proposal) do |**kwargs|
      pedidos << kwargs[:insurer_code]
      raise Autonomia::Insurance::Connector::Error.new(:unavailable, 'X-Amz-Signature=abc') if codigos.include?(kwargs[:insurer_code])

      { 'quote_id' => kwargs[:quote_id], 'url' => "https://arquivos.exemplo.test/proposta-#{kwargs[:insurer_code]}.pdf" }
    end
  end

  it 'e assincrona: gerar a proposta e chamada ao portal de ate 60 s, e o turno nao espera' do
    expect(described_class.async?).to be(true)
  end

  # ARRAY OBRIGATÓRIO em strict mode: fora de `required` (ou anulável) o agente fica MUDO.
  it 'declara `seguradoras` como array de texto obrigatorio, sem null' do
    schema = described_class.openai_schema
    parametro = schema[:parameters][:properties]['seguradoras']

    expect(schema[:parameters][:required]).to eq(['seguradoras'])
    expect(parametro['type']).to eq('array')
    expect(parametro['items']).to eq('type' => 'string')
  end

  # A ORIGEM É ESCOLHIDA UMA VEZ, NO TURNO, e gravada nos argumentos da execução (Codex, P1).
  describe '#argumentos — o aceite fixa a cotacao de origem' do
    it 'grava, junto do que o modelo escreveu, a cotacao escolhida no turno' do
      linha = cotacao_com_precos

      expect(no_turno('Porto').argumentos).to eq('seguradoras' => ['Porto'], described_class::ORIGEM => linha.id)
    end

    it 'sem cotacao na conversa, devolve so o que o modelo escreveu' do
      expect(no_turno('Porto').argumentos).to eq('seguradoras' => ['Porto'])
    end

    # Nunca uma morta: a supersedida é a que o cliente mandou refazer. A mais recente das vivas ou
    # encerradas com preço é a que ele está lendo.
    it 'escolhe a mais recente com preco que nao morreu, mesmo havendo uma supersedida mais nova' do
      antiga = cotacao_com_precos(quote_id: 'antiga')
      cotacao_com_precos(quote_id: 'refeita', status: 'superseded')

      expect(no_turno('Porto').argumentos[described_class::ORIGEM]).to eq(antiga.id)
    end

    it 'a cotacao viva com preco parcial e origem: e a lista que o cliente esta lendo' do
      parcial = cotacao_com_precos(status: 'running')

      expect(no_turno('Porto').argumentos[described_class::ORIGEM]).to eq(parcial.id)
    end

    # O ACEITE PELO CAMINHO REAL (`Bound#execute`), e não pela chamada direta a `#argumentos`: é o
    # `Bound` quem grava os argumentos da execução, e gravar ali o que o MODELO escreveu (em vez de
    # `ferramenta.argumentos`) faria a origem nunca ser fixada — a mutação MB reprova aqui.
    it 'o aceite grava a origem nos argumentos da execucao, pelo caminho do Bound' do
      # Arrange
      linha = cotacao_com_precos
      bound = Autonomia::Agents::Tools::Bound.new(agent: agent, native: described_class)

      # Act
      saida = bound.execute({ 'name' => described_class.slug, 'arguments' => { seguradoras: ['Porto'] }.to_json },
                            delivery: delivery)

      # Assert
      expect(saida).to eq(described_class::ACEITA)
      expect(delivery.runs.sole.arguments).to eq('seguradoras' => ['Porto'], described_class::ORIGEM => linha.id)
    end
  end

  describe '#start — a proposta da escolhida (termo 1)' do
    it 'pede ao portal a proposta da seguradora escolhida, pelo codigo do mapa da cotacao, e nao o comparativo' do
      # Arrange
      cotacao_com_precos

      # Act
      handle = no_job('Porto').start

      # Assert
      expect(handle[described_class::GERADAS]).to eq([{ 'code' => '8', 'name' => 'Porto', 'url' => 'https://arquivos.exemplo.test/proposta-8.pdf' }])
      expect(handle[described_class::PENDENTES]).to eq([])
      expect(handle['quote_id']).to eq('q1')
      expect(connector).to have_received(:quote_proposal).with(hash_including(insurer_code: '8', quote_id: 'q1')).once
      expect(connector).not_to have_received(:quote_start)
    end

    it 'casa o nome como o cliente escreveu: maiuscula, acento e espaco a mais nao importam' do
      cotacao_com_precos(mapa: nomes.merge('3' => 'Mapfre São Paulo'))

      expect(no_job('  PORTO ').start[described_class::GERADAS].pluck('code')).to eq(['8'])
      expect(no_job('mapfre sao  paulo').start[described_class::GERADAS].pluck('code')).to eq(['3'])
    end

    it 'casa pelo prefixo quando ele e de um nome so' do
      cotacao_com_precos

      expect(no_job('Suh').start[described_class::GERADAS].pluck('code')).to eq(['20'])
    end

    # NADA DE SEMELHANÇA: um nome que não é prefixo de ninguém não cotou, mesmo que "pareça".
    it 'nao casa por semelhanca: "Portu" nao e Porto' do
      cotacao_com_precos

      handle = no_job('Portu').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(connector).not_to have_received(:quote_proposal)
    end

    # PREFIXO, NÃO PEDAÇO (mutação M1 da rodada de correção): "assinatura" está DENTRO de "Bp
    # Assinatura", e mesmo assim não é ela — `include?` no lugar de `start_with?` mandaria a 55.
    it 'nao casa por pedaco do nome: "assinatura" nao e Bp Assinatura' do
      cotacao_com_precos

      handle = no_job('assinatura').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(connector).not_to have_received(:quote_proposal)
    end

    # O CASO REAL DO HOMÔNIMO (Codex, P2): no portal, 48 chama-se "Bp" e 55 "Bp Assinatura". O
    # EXATO VENCE — sem esta regra a 48 era inselecionável, porque todo prefixo de "bp" casa as duas.
    it 'homonimo: "Bp" com 48 e 55 cotadas e a 48, porque o nome exato vence' do
      cotacao_com_precos

      handle = no_job('Bp').start

      expect(handle[described_class::GERADAS].pluck('code')).to eq(['48'])
      expect(connector).to have_received(:quote_proposal).with(hash_including(insurer_code: '48')).once
    end

    it 'sem exato, o prefixo de mais de um nome e ambiguo, e a resposta lista as candidatas' do
      cotacao_com_precos

      handle = no_job('B').start

      expect(handle['motivo']).to eq('seguradora_ambigua')
      expect(handle['pedido']).to include('B pode ser Bp ou Bp Assinatura')
      expect(handle['faltando']).to eq(['seguradoras'])
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'sem exato, o prefixo de um so casa: "bp a" e a Bp Assinatura' do
      cotacao_com_precos

      expect(no_job('bp a').start[described_class::GERADAS].pluck('code')).to eq(['55'])
    end

    it '"Bp Assinatura" e uma so, mesmo com a Bp cotada' do
      cotacao_com_precos

      expect(no_job('Bp Assinatura').start[described_class::GERADAS].pluck('code')).to eq(['55'])
    end

    it 'quando so a Bp Assinatura cotou, "Bp" e ela' do
      cotacao_com_precos(mapa: nomes.except('48'))

      expect(no_job('Bp').start[described_class::GERADAS].pluck('code')).to eq(['55'])
    end

    it 'dois nomes que casam com a mesma seguradora sao UMA proposta' do
      cotacao_com_precos

      handle = no_job('Porto', 'porto').start

      expect(handle[described_class::GERADAS].pluck('code')).to eq(['8'])
      expect(handle[described_class::PENDENTES]).to eq([])
      expect(connector).to have_received(:quote_proposal).once
    end
  end

  # TERMO 3 — se a seguradora pedida não cotou, a resposta diz isso e lista quem cotou, em vez de
  # mandar o comparativo de todas em silêncio. E nenhuma chamada ao portal.
  describe '#start — quem nao cotou (termo 3)' do
    it 'diz que nao tem preco daquela e lista quem cotou' do
      cotacao_com_precos

      handle = no_job('Zurich').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(handle['pedido']).to include('Não tenho preço de Zurich nesta cotação')
      expect(handle['pedido']).to include('Porto', 'Bp', 'Bp Assinatura', 'Suhai')
      expect(handle['pedido']).not_to include('Comparativo')
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'com duas pedidas e uma que nao cotou, a resposta e a recusa daquela — sem mandar a outra em silencio' do
      cotacao_com_precos

      handle = no_job('Porto', 'Zurich').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(handle['pedido']).to include('Zurich')
      expect(connector).not_to have_received(:quote_proposal)
    end

    # O PORTAL DIZENDO 422 PARA QUEM ESTÁ NO MAPA NÃO É "NÃO COTOU" (verificador cego, B1): o cliente
    # acabou de ler o preço dela. É "não consegui gerar", com motivo próprio — nunca a frase
    # autocontraditória "não tenho preço de Porto… quem cotou: Porto".
    it 'o portal recusando (422) a seguradora que cotou vira "nao consegui gerar", nunca "nao cotou"' do
      cotacao_com_precos
      portal_que_recusa('8')

      handle = no_job('Porto').start

      expect(handle['motivo']).to eq('proposta_nao_gerada')
      expect(handle['pedido']).to include('Não consegui gerar a proposta de Porto agora')
      expect(handle['pedido']).not_to include('Não tenho preço', 'Quem cotou')
    end
  end

  # O PORTAL FALHANDO NÃO LEVANTA NEM DESISTE (Codex, P2): a seguradora fica PENDENTE para a passada
  # seguinte, até `MAX_TENTATIVAS`. O que falha ANTES da chamada — sessão, credencial, código em
  # branco — sobe como sempre (verificador cego, B2).
  describe '#start — o portal falha, a nossa parte falha' do
    it 'a falha do portal (503) nao levanta: a seguradora fica pendente, com a tentativa contada' do
      cotacao_com_precos
      portal_fora_do_ar_para('8')

      handle = no_job('Porto').start

      expect(handle[described_class::GERADAS]).to eq([])
      expect(handle[described_class::PENDENTES]).to eq(['8'])
      expect(handle[described_class::TENTATIVAS]).to eq('8' => 1)
      expect(handle['motivo']).to be_nil
    end

    it 'resposta do portal sem URL e falha do portal (protocol), nao proposta vazia' do
      cotacao_com_precos
      allow(connector).to receive(:quote_proposal).and_return({ 'quote_id' => 'q1' })

      handle = no_job('Porto').start
      segunda = no_job('Porto').poll(handle: handle, attempt: 1)

      expect(handle[described_class::PENDENTES]).to eq(['8'])
      expect(segunda.handle[described_class::NAO_SAIU]).to eq('8' => 'protocol')
      expect(segunda.handle[described_class::PENDENTES]).to eq([])
    end

    # O `rescue` só envolve a chamada ao portal: a sessão falhando é problema NOSSO e sobe, para o
    # job tentar de novo — e nunca vira "a seguradora não gerou" (mutação MR reprova aqui).
    it 'credencial ausente na conexao sobe como erro, sem virar "nao gerou" e sem chamar o portal' do
      cotacao_com_precos
      conexao.forget_session!
      conexao.update!(password: '')

      expect { no_job('Porto').start }.to raise_error(Autonomia::Insurance::Connector::Error) { |e| expect(e.kind).to eq(:validation) }
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'login recusado pelo portal sobe como erro, sem virar "nao gerou"' do
      cotacao_com_precos
      conexao.forget_session!
      allow(connector).to receive(:open_session).and_raise(Autonomia::Insurance::Connector::Error.new(:auth_required, 'recusado'))

      expect { no_job('Porto').start }.to raise_error(Autonomia::Insurance::Connector::Error) { |e| expect(e.kind).to eq(:auth_required) }
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'sem conexao pronta sobe como erro de configuracao' do
      cotacao_com_precos
      conexao.update!(status: 'degraded')

      expect { no_job('Porto').start }.to raise_error(Autonomia::Insurance::Connector::Error) { |e| expect(e.kind).to eq(:config) }
    end

    # CÓDIGO VAZIO NUNCA CHEGA AO PORTAL (verificador cego, A; mutação MV): `quote_proposal` sem
    # `insurerCode` é o comparativo de TODAS com nome de proposta. O mapa da cotação já não grava
    # código vazio; se um chegar aqui, é defeito nosso e sobe antes do conector.
    it 'codigo de seguradora em branco no mapa nunca vira pedido ao portal' do
      cotacao_com_precos(mapa: nomes.merge('' => 'Fantasma'))

      expect { no_job('Fantasma').start }.to raise_error(Autonomia::Insurance::Connector::Error) { |e| expect(e.kind).to eq(:protocol) }
      expect(connector).not_to have_received(:quote_proposal)
    end
  end

  # TERMO 4 — duas seguradoras, dois arquivos, na MESMA execução; e nenhuma cotação nova. UMA chamada
  # ao portal por passada: o `start` pede a primeira e deixa a segunda pendente para o `poll`.
  describe '#start e #poll — duas seguradoras (termo 4)' do
    it 'o start pede so a primeira; o poll entrega a que saiu e so depois pede a segunda, sem abrir cotacao' do
      cotacao_com_precos
      run = execucao('Porto', 'Suhai')

      handle = no_job('Porto', 'Suhai', run: run).start
      primeira = no_job('Porto', 'Suhai', run: run).poll(handle: handle, attempt: 1)
      publicar_entrega!(run, conversation, primeira.deliveries.first)
      segunda = no_job('Porto', 'Suhai', run: run).poll(handle: primeira.handle, attempt: 2)

      expect(handle[described_class::PENDENTES]).to eq(['20'])
      expect(arquivo(primeira.deliveries.first).nome).to eq('Proposta Porto — placa ABC1D23.pdf')
      expect(segunda).to be_running
      expect(segunda.deliveries).to be_empty
      expect(segunda.handle[described_class::GERADAS].pluck('code')).to eq(%w[8 20])
      expect(pedidos).to eq(%w[8 20])
      expect(connector).not_to have_received(:quote_start)
    end

    # O CENÁRIO DO CODEX (P2): Porto sai, Suhai 503. A Porto chega NA PRIMEIRA passada de entrega
    # (geradas antes das pendentes), o aviso é sobre a Suhai, e a Porto NÃO é pedida de novo — a URL
    # dela ficou no handle da primeira passada.
    it 'Porto sai e Suhai falha: a Porto chega, o aviso e sobre a Suhai, e a Porto nao e refeita' do
      linha = cotacao_com_precos
      portal_fora_do_ar_para('20')
      run = execucao('Porto', 'Suhai')
      ferramenta = -> { no_job('Porto', 'Suhai', run: run) }

      handle = ferramenta.call.start
      entrega = ferramenta.call.poll(handle: handle, attempt: 1)
      publicar_entrega!(run, conversation, entrega.deliveries.first)
      tentativa1 = ferramenta.call.poll(handle: entrega.handle, attempt: 2)
      tentativa2 = ferramenta.call.poll(handle: tentativa1.handle, attempt: 3)
      aviso = ferramenta.call.poll(handle: tentativa2.handle, attempt: 4)

      expect(arquivo(entrega.deliveries.first).nome).to eq('Proposta Porto — placa ABC1D23.pdf')
      expect(tentativa1.handle[described_class::TENTATIVAS]).to eq('20' => 1)
      expect(tentativa2.handle[described_class::NAO_SAIU]).to eq('20' => 'unavailable')
      expect(aviso).to be_done
      expect(aviso.deliveries).to eq(['Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima.'])
      expect(pedidos).to eq(%w[8 20 20])
      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(['8'])
    end

    it 'quando o portal recusa (422) uma das duas, a recusa e definitiva: sai a que saiu e o aviso da outra' do
      cotacao_com_precos
      portal_que_recusa('20')
      run = execucao('Porto', 'Suhai')

      handle = no_job('Porto', 'Suhai', run: run).start
      primeira = no_job('Porto', 'Suhai', run: run).poll(handle: handle, attempt: 1)
      publicar_entrega!(run, conversation, primeira.deliveries.first)
      segunda = no_job('Porto', 'Suhai', run: run).poll(handle: primeira.handle, attempt: 2)
      terceira = no_job('Porto', 'Suhai', run: run).poll(handle: segunda.handle, attempt: 3)

      expect(segunda.handle[described_class::NAO_SAIU]).to eq('20' => 'validation')
      expect(segunda.handle[described_class::PENDENTES]).to eq([])
      expect(terceira.deliveries.last).to eq('Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima.')
    end

    it 'quando a primeira e recusada (422) e a segunda sai, a entrega e a segunda com o aviso da primeira' do
      cotacao_com_precos
      portal_que_recusa('8')
      run = execucao('Porto', 'Suhai')

      handle = no_job('Porto', 'Suhai', run: run).start
      pedida = no_job('Porto', 'Suhai', run: run).poll(handle: handle, attempt: 1)
      entrega = no_job('Porto', 'Suhai', run: run).poll(handle: pedida.handle, attempt: 2)
      publicar_entrega!(run, conversation, entrega.deliveries.first)
      fim = no_job('Porto', 'Suhai', run: run).poll(handle: entrega.handle, attempt: 3)

      expect(handle['motivo']).to be_nil
      expect(handle[described_class::PENDENTES]).to eq(['20'])
      expect(arquivo(entrega.deliveries.first).nome).to eq('Proposta Suhai — placa ABC1D23.pdf')
      expect(fim.deliveries).to eq(['Não consegui gerar a proposta de Porto agora; as demais estão aqui em cima.'])
    end

    it 'quando NENHUMA sai, o cliente le que nao consegui gerar, e nao "nao cotou"' do
      cotacao_com_precos
      portal_que_recusa('8', '20')

      handle = no_job('Porto', 'Suhai').start
      segunda = no_job('Porto', 'Suhai').poll(handle: handle, attempt: 1)
      entrega = no_job('Porto', 'Suhai').poll(handle: segunda.handle, attempt: 2)

      expect(entrega).to be_done
      expect(entrega.deliveries).to eq(['Não consegui gerar a proposta de Porto e Suhai agora. Posso tentar de novo daqui a pouco, ' \
                                        'ou um atendente retoma daqui.'])
    end

    it 'mais de duas e recusa nomeada, antes de qualquer chamada' do
      cotacao_com_precos

      handle = no_job('Porto', 'Suhai', 'Bp Assinatura').start

      expect(handle['motivo']).to eq('proposta_acima_do_teto')
      expect(handle['pedido']).to include('até duas')
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'nenhuma seguradora e recusa nomeada' do
      cotacao_com_precos

      expect(no_job.start['motivo']).to eq('proposta_sem_seguradora')
      expect(no_job('  ').start['motivo']).to eq('proposta_sem_seguradora')
    end
  end

  # A ORIGEM FIXADA (Codex, P1): o `start` usa a que o aceite gravou, e só ela; se ela morreu, ou se
  # há uma cotação nova correndo, a resposta é nomeada e o portal não é chamado.
  describe '#start — qual cotacao' do
    # EXECUÇÃO SEM ORIGEM FIXADA é recusa PRÓPRIA (rodada 3, M4): é o que acontece com uma linha
    # `pending` aberta antes do deploy que passou a fixar a origem no aceite. Não é "não encontrei
    # cotação" — pode haver uma, e o que se perdeu foi a escolha do turno; escolher agora, no job,
    # é justamente o que a rodada 2 proibiu. O texto pede o pedido de novo, que já nasce com origem.
    it 'sem a origem fixada nos argumentos, o job nao escolhe: recusa propria, sem tocar no portal' do
      cotacao_com_precos

      handle = no_job_com_origem(nil, 'Porto').start

      expect(handle['motivo']).to eq('proposta_sem_origem')
      expect(handle['pedido']).to eq(described_class::SEM_ORIGEM)
      expect(connector).not_to have_received(:quote_proposal)
    end

    # A ORIGEM É SEMPRE DESTA CONVERSA (rodada 3, M1): o id vem dos nossos argumentos, mas
    # `cotacao_fixada` filtra por conta E conversa — tirar esse escopo (mutação MS) faria a proposta
    # sair da cotação de outro cliente da mesma corretora.
    it 'a cotacao de OUTRA conversa nao conta, mesmo fixada pelo id' do
      alheia = cotacao_com_precos(conversa: create(:conversation, account: account, inbox: inbox, assignee: nil))

      handle = no_job_com_origem(alheia, 'Porto').start

      expect(handle['motivo']).to eq('proposta_sem_cotacao')
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'a cotacao sem preco entregue nao conta' do
      sem_preco = cotacao_com_precos(mapa: {})

      expect(no_job_com_origem(sem_preco, 'Porto').start['motivo']).to eq('proposta_sem_cotacao')
    end

    # A cotação anterior à entrega 8 tem `entregues` e não tem o mapa: não há como casar o nome.
    it 'a cotacao anterior a entrega 8, sem o mapa de nomes, nao conta' do
      velha = Autonomia::Agents::ToolRun.create!(account: account, agent: agent, conversation_id: conversation.id, slug: cotacao.slug,
                                                 status: 'done', execution_key: SecureRandom.uuid, arguments: {},
                                                 handle: { 'quote_id' => 'velha', cotacao::DELIVERED_KEY => ['8'] })

      expect(no_job_com_origem(velha, 'Porto').start['motivo']).to eq('proposta_sem_cotacao')
    end

    # `pending` ÓRFÃ NÃO É COTAÇÃO EM ANDAMENTO (verificador cego, I2): o worker morreu entre o
    # aceite e o despacho — um deploy basta —, e a linha fica parada até o prazo, sem ninguém para
    # executá-la. Contá-la travaria a proposta por uma cotação que nunca vai acontecer; é a mesma
    # convenção de `ToolRun.opened_for_turn?`. A mutação MI (`active?` de volta) reprova aqui.
    it 'a cotacao aceita e nunca promovida nao barra a proposta' do
      cotacao_com_precos
      Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, arguments: { 'produto' => 'auto' },
                                       scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })

      handle = no_job('Porto').start

      expect(handle['motivo']).to be_nil
      expect(handle[described_class::GERADAS].pluck('code')).to eq(['8'])
    end

    # O CENÁRIO DO CODEX: A cotou, o cliente corrigiu o veículo e abriu B. "Me manda a da Porto"
    # durante B não pode gerar a proposta de A — a resposta é que a cotação nova está em andamento.
    it 'A cotou e B esta correndo sem preco: recusa "em andamento", no turno e no envio, sem portal' do
      cotacao_com_precos(quote_id: 'A')
      cotacao_nova_em_andamento

      conferencia = no_turno('Porto').precheck
      handle = no_job_com_origem(Autonomia::Agents::ToolRun.find_by(slug: cotacao.slug, status: 'done'), 'Porto').start

      expect(conferencia.motivo).to eq('cotacao_em_andamento')
      expect(conferencia.to_s).to include('Ainda estou buscando os preços da cotação nova')
      expect(handle['motivo']).to eq('cotacao_em_andamento')
      expect(connector).not_to have_received(:quote_proposal)
    end

    # ORIGEM SUPERSEDIDA ENTRE O ACEITE E O START: a lista parcial era a origem; um pedido novo a
    # supersedeu antes do job rodar. Nada sai do portal.
    it 'a origem supersedida entre o aceite e o start e recusa nomeada, sem chamar o portal' do
      cotacao_com_precos(status: 'running')
      argumentos = no_turno('Porto').argumentos
      cotacao_nova_em_andamento

      handle = described_class.new(agent: agent, params: argumentos, conversation: conversation).start

      expect(handle['motivo']).to eq('cotacao_substituida')
      expect(handle['pedido']).to include('A cotação foi refeita depois desse pedido')
      expect(connector).not_to have_received(:quote_proposal)
    end

    # O START USA SÓ A ORIGEM FIXADA (mutação MO reprova aqui): uma cotação MAIS NOVA com preço,
    # encerrada depois do aceite, não troca a origem — a proposta é da lista que o cliente leu ao pedir.
    it 'o start usa a origem fixada no aceite, e nao a ultima cotacao com preco da conversa' do
      origem = cotacao_com_precos(quote_id: 'fixada')
      cotacao_com_precos(quote_id: 'mais-nova')

      handle = no_job_com_origem(origem, 'Porto').start

      expect(handle['quote_id']).to eq('fixada')
      expect(connector).to have_received(:quote_proposal).with(hash_including(quote_id: 'fixada')).once
    end

    it 'guarda no handle o que o poll precisa: a origem e o sufixo do nome do arquivo' do
      linha = cotacao_com_precos

      handle = no_job('Porto').start

      expect(handle[described_class::ORIGEM]).to eq(linha.id)
      expect(handle['sufixo']).to eq('placa ABC1D23')
    end
  end

  # A CONFERÊNCIA DO TURNO: o que dá para saber sem o portal responde ao modelo na hora, e nenhuma
  # execução é aberta. O portal NUNCA é chamado dentro do turno — nem login, nem proposta.
  describe '#precheck — no turno, sem portal' do
    it 'devolve ao modelo a ambiguidade, com as candidatas, e nao toca no portal' do
      cotacao_com_precos

      conferencia = no_turno('B').precheck

      expect(conferencia).to be_a(Autonomia::Agents::Tools::Native::Conferencia)
      expect(conferencia.motivo).to eq('seguradora_ambigua')
      expect(conferencia.to_s).to include('Bp Assinatura')
      expect(conferencia.faltando).to eq(['seguradoras'])
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'devolve ao modelo quem nao cotou, com a lista de quem cotou' do
      cotacao_com_precos

      conferencia = no_turno('Zurich').precheck

      expect(conferencia.motivo).to eq('seguradora_nao_cotou')
      expect(conferencia.to_s).to include('Quem cotou: Bp, Bp Assinatura, Porto e Suhai')
    end

    it 'sem cotacao na conversa, diz isso ao modelo' do
      expect(no_turno('Porto').precheck.motivo).to eq('proposta_sem_cotacao')
    end

    it 'deixa passar quando ha o que gerar — e ainda assim nao chama o portal no turno' do
      cotacao_com_precos

      expect(no_turno('Porto', 'Suhai').precheck).to be_nil
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'sem sessao viva o turno segue igual: a conferencia nao depende do portal' do
      cotacao_com_precos
      conexao.forget_session!

      expect(no_turno('Porto').precheck).to be_nil
      expect(no_turno('B').precheck.motivo).to eq('seguradora_ambigua')
    end
  end

  describe '#poll — um arquivo por passada, confirmado pela mensagem' do
    let(:linha) { cotacao_com_precos }
    let(:run) do
      origem = linha
      execucao(argumentos: { 'seguradoras' => %w[Porto Suhai], described_class::ORIGEM => origem.id })
    end

    def handle
      { 'quote_id' => 'q1', described_class::ORIGEM => linha.id, 'sufixo' => 'placa ABC1D23',
        described_class::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => 'https://arquivos.exemplo.test/proposta-8.pdf' },
                                     { 'code' => '20', 'name' => 'Suhai', 'url' => 'https://arquivos.exemplo.test/proposta-20.pdf' }],
        described_class::PENDENTES => [], described_class::NAO_SAIU => {}, described_class::ENVIADAS => [] }
    end

    def passada(entrada, attempt)
      no_job('Porto', 'Suhai', run: run).poll(handle: entrada, attempt: attempt)
    end

    # A entrega de uma passada vira MENSAGEM, com o token que o publicador carimba (o caminho real —
    # publicador, download, anexo — está em «pelo job»).
    def publicar!(progresso)
      publicar_entrega!(run, conversation, progresso.deliveries.first)
      progresso
    end

    # UM ARQUIVO POR PASSADA (mutação M8): cada `EntregaDeArquivo` é um download de até 20 s, e dois
    # na mesma passada passariam dos 25 s que o Sidekiq dá ao job num shutdown. E A PASSADA SEGUINTE
    # CONFIRMA: a execução só encerra depois de o último arquivo virar mensagem, porque é a mensagem
    # — não o handle — que diz que ele chegou (mutação ME).
    it 'entrega um arquivo por passada e so encerra depois de o ultimo virar mensagem' do
      primeira = publicar!(passada(handle, 1))
      segunda = publicar!(passada(primeira.handle, 2))
      terceira = passada(segunda.handle, 3)

      expect([primeira, segunda].map(&:deliveries).map(&:size)).to eq([1, 1])
      expect(primeira.handle[described_class::ENVIADAS]).to eq([])
      expect(segunda).to be_running
      expect(segunda.handle[described_class::ENVIADAS]).to eq(['8'])
      expect(terceira).to be_done
      expect(terceira.deliveries).to be_empty
      expect(terceira.handle[described_class::ENVIADAS]).to eq(%w[8 20])
    end

    # PUBLICAÇÃO QUE NÃO VIROU MENSAGEM (o publicador devolveu `blocked`: autorização caída, banco,
    # conversa travada): o arquivo VOLTA na passada seguinte, e a cotação só é marcada quando a
    # mensagem existe. Com a decisão pelo handle (mutação ME) o arquivo era contado como enviado sem
    # existir, e o cliente ficava sem nada.
    it 'reentrega o arquivo cuja publicacao nao virou mensagem, e so anota depois que ela existe' do
      primeira = passada(handle, 1)
      segunda = passada(primeira.handle, 2)

      expect(arquivo(segunda.deliveries.first).nome).to eq(arquivo(primeira.deliveries.first).nome)
      expect(segunda.handle[described_class::ENVIADAS]).to eq([])
      expect(linha.reload.handle).not_to have_key(cotacao::PROPOSTAS_KEY)

      publicar_entrega!(run, conversation, segunda.deliveries.first)
      terceira = passada(segunda.handle, 3)

      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(['8'])
      expect(arquivo(terceira.deliveries.first).nome).to include('Suhai')
    end

    it 'nomeia cada arquivo pela seguradora e pela placa, com legenda e reserva' do
      primeira = publicar!(passada(handle, 1))
      segunda = passada(primeira.handle, 2)
      arquivos = [arquivo(primeira.deliveries.first), arquivo(segunda.deliveries.first)]

      expect(arquivos.map(&:nome)).to eq(['Proposta Porto — placa ABC1D23.pdf', 'Proposta Suhai — placa ABC1D23.pdf'])
      expect(arquivos.map(&:legenda)).to eq(['Proposta da Porto.', 'Proposta da Suhai.'])
      expect(arquivos.first.reserva).to eq("Proposta da Porto:\nhttps://arquivos.exemplo.test/proposta-8.pdf")
      expect(arquivos.first.url).to eq('https://arquivos.exemplo.test/proposta-8.pdf')
    end

    it 'nomeia pelo ramo quando a cotacao nao tem placa' do
      progresso = passada(handle.merge('sufixo' => 'fianca locaticia'), 1)

      expect(arquivo(progresso.deliveries.first).nome).to eq('Proposta Porto — fianca locaticia.pdf')
    end

    # O REGISTRO É NA LINHA DA COTAÇÃO, que já está `done`: é ela que "virou proposta", e é lá que a
    # medida da entrega 7 lê. Uma escrita que exigisse linha viva contaria zero para sempre.
    it 'anota na linha da COTACAO quais propostas sairam, e a medida conta' do
      primeira = publicar!(passada(handle, 1))
      segunda = publicar!(passada(primeira.handle, 2))
      terceira = passada(segunda.handle, 3)

      expect(terceira.handle).not_to have_key(cotacao::PROPOSTAS_KEY)
      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(%w[20 8])
      expect(linha.status).to eq('done')
      expect(Autonomia::Insurance::Medida.new(conta: account, inicio: nil, fim: nil).call)
        .to include(cotacoes: 1, cotacoes_com_proposta: 1, propostas_emitidas: 2)
    end

    # A COTAÇÃO VIVA TAMBÉM É ANOTADA (mutação M2 reprova aqui): o cliente escolhe na lista parcial,
    # e a proposta sai com a cotação ainda `running` — ou encerrada em `failed` depois de entregar
    # preço. Só as MORTAS não recebem proposta, e quem barra é o `poll`, antes de anotar.
    it 'anota tambem na cotacao ainda viva, e na encerrada por prazo com preco entregue' do
      viva = cotacao_com_precos(status: 'running', quote_id: 'viva')
      publicar!(passada(handle.merge(described_class::ORIGEM => viva.id), 1))
      passada(handle.merge(described_class::ORIGEM => viva.id), 2)
      viva.update!(status: 'done')
      vencida = cotacao_com_precos(status: 'failed', quote_id: 'vencida')
      passada(handle.merge(described_class::ORIGEM => vencida.id), 1)

      expect(viva.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(['8'])
      expect(vencida.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(['8'])
    end

    it 'a passada repetida nao duplica a anotacao nem a entrega' do
      primeira = publicar!(passada(handle, 1))
      segunda = publicar!(passada(primeira.handle, 2))
      terceira = passada(segunda.handle, 3)
      repetida = passada(segunda.handle, 4)

      expect(terceira).to be_done
      expect(repetida).to be_done
      expect(repetida.deliveries).to be_empty
      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(%w[20 8])
    end

    it 'entrega o aviso da seguradora que o portal nao gerou depois do ULTIMO arquivo' do
      so_porto = handle.merge(described_class::GERADAS => handle[described_class::GERADAS].first(1),
                              described_class::NAO_SAIU => { '20' => 'validation' })

      primeira = publicar!(passada(so_porto, 1))
      segunda = passada(primeira.handle, 2)

      expect(primeira.deliveries.size).to eq(1)
      expect(segunda).to be_done
      expect(segunda.deliveries).to eq(['Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima.'])
    end

    # GERADAS ANTES DAS PENDENTES (mutação MG, P2 do Codex): com a Porto pronta e a Suhai por pedir,
    # a passada ENTREGA a Porto — não gasta a passada, e o prazo, numa chamada ao portal de até 60 s.
    # Só quando não há mais nada por entregar é que a pendente é pedida.
    it 'entrega a proposta pronta antes de pedir a pendente ao portal' do
      pendente = handle.merge(described_class::GERADAS => handle[described_class::GERADAS].first(1),
                              described_class::PENDENTES => ['20'])

      primeira = publicar!(passada(pendente, 1))
      segunda = passada(primeira.handle, 2)

      expect(arquivo(primeira.deliveries.first).nome).to eq('Proposta Porto — placa ABC1D23.pdf')
      expect(primeira.handle[described_class::PENDENTES]).to eq(['20'])
      expect(segunda).to be_running
      expect(segunda.deliveries).to be_empty
      expect(segunda.handle[described_class::GERADAS].pluck('code')).to eq(%w[8 20])
      expect(pedidos).to eq(['20'])
    end

    # ORIGEM SUPERSEDIDA ENTRE O START E O POLL: o arquivo já foi gerado, mas a cotação de que ele
    # saiu foi refeita. Não entrega, não anota, e o cliente lê o porquê.
    it 'a origem supersedida entre o start e o poll e recusa nomeada: nada e entregue nem anotado' do
      viva = cotacao_com_precos(status: 'running')
      cotacao_nova_em_andamento

      progresso = passada(handle.merge(described_class::ORIGEM => viva.id), 1)

      expect(viva.reload.status).to eq('superseded')
      expect(progresso).to be_done
      expect(progresso.deliveries).to eq([described_class::SUBSTITUIDA])
      expect(viva.handle).not_to have_key(cotacao::PROPOSTAS_KEY)
    end

    # A COTAÇÃO NOVA CORRENDO TAMBÉM BARRA O `poll` (verificador cego, I1; mutação MA): uma origem
    # `done` NÃO vira `superseded` quando outra abre, então `dead?` sozinho deixava a proposta da
    # lista velha sair enquanto o cliente esperava os preços novos — o mesmo pedido que o `start`
    # recusa. A janela é de dezenas de segundos a minutos, não "de segundos".
    it 'a cotacao nova em andamento entre o start e o poll barra a entrega, e o cliente le o porque' do
      run
      cotacao_nova_em_andamento

      progresso = passada(handle, 1)

      expect(progresso).to be_done
      expect(progresso.deliveries).to eq([described_class::EM_ANDAMENTO])
      expect(linha.reload.handle).not_to have_key(cotacao::PROPOSTAS_KEY)
      expect(conversation.messages.count).to be_zero
    end

    it 'sem a origem no handle (ou apagada), falha nomeada: nao ha como conferir se ela ainda vale' do
      progresso = passada(handle.except(described_class::ORIGEM), 1)

      expect(progresso).to be_failed
      expect(progresso.failure_code).to eq('cotacao_ausente')
    end

    it 'entrega a recusa do start ao cliente e acaba' do
      progresso = passada({ 'pedido' => 'Não tenho preço de Zurich.', 'motivo' => 'seguradora_nao_cotou' }, 1)

      expect(progresso).to be_done
      expect(progresso.deliveries).to eq(['Não tenho preço de Zurich.'])
    end

    # A URL VEM DE FORA: se não cabe na forma segura, vai o link em texto — a falha da forma não
    # apaga a entrega (a mesma regra do comparativo).
    it 'quando a URL do portal nao tem a forma segura, entrega o link em texto' do
      inseguro = handle.merge(described_class::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => 'http://arquivos.exemplo.test/p.pdf' }])

      progresso = passada(inseguro, 1)

      expect(progresso.deliveries).to eq(["Proposta da Porto:\nhttp://arquivos.exemplo.test/p.pdf"])
    end

    # E a reserva publicada também conta como entregue: a identidade é a MESMA nos dois caminhos.
    it 'o link de reserva publicado encerra a entrega daquela proposta' do
      inseguro = handle.merge(described_class::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => 'http://arquivos.exemplo.test/p.pdf' }])

      primeira = publicar!(passada(inseguro, 1))
      segunda = passada(primeira.handle, 2)

      expect(segunda).to be_done
      expect(segunda.deliveries).to be_empty
      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(['8'])
    end

    it 'falha nomeada quando o handle nao tem proposta, pendente nem falha registrada' do
      progresso = passada(handle.merge(described_class::GERADAS => []), 1)

      expect(progresso).to be_failed
      expect(progresso.failure_code).to eq('sem_proposta')
    end
  end

  # O QUE AINDA VALE ENTREGAR QUANDO O PRAZO ACABA (Codex, rodada 2, P2): o arquivo que o portal
  # gerou e não chegou ao cliente, e o aviso de quem ficou pelo caminho — pendente no fim é, para
  # quem espera, o mesmo que não gerada.
  describe '#closing_deliveries — o encerramento por prazo' do
    let(:linha) { cotacao_com_precos }
    let(:run) do
      origem = linha
      execucao(argumentos: { 'seguradoras' => %w[Porto Suhai], described_class::ORIGEM => origem.id })
    end

    def handle
      { 'sufixo' => 'placa ABC1D23', described_class::ORIGEM => linha.id,
        described_class::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => 'https://arquivos.exemplo.test/proposta-8.pdf' }],
        described_class::PENDENTES => ['20'] }
    end

    # Mutação MC (o fechamento sem as geradas) reprova aqui.
    it 'entrega a proposta gerada que nao virou mensagem, e avisa de quem ficou pelo caminho' do
      entregas = no_job('Porto', 'Suhai', run: run).closing_deliveries(handle)

      expect(entregas.map { |item| arquivo(item)&.nome || item })
        .to eq(['Proposta Porto — placa ABC1D23.pdf',
                'Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima.'])
    end

    it 'nao repete o que ja virou mensagem' do
      publicar_entrega!(run, conversation, no_job('Porto', 'Suhai', run: run).closing_deliveries(handle).first)

      entregas = no_job('Porto', 'Suhai', run: run).closing_deliveries(handle)

      expect(entregas).to eq(['Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima.'])
    end

    it 'nao entrega nada quando a cotacao de origem foi refeita' do
      run
      cotacao_nova_em_andamento

      expect(no_job('Porto', 'Suhai', run: run).closing_deliveries(handle)).to be_empty
    end
  end

  # A ORIGEM RECONFERIDA NA PUBLICAÇÃO EFETIVA (Codex, rodada 2, P1). Entre o `poll` e a mensagem há
  # a cadeia de entrega humanizada (até 90 s) e a retomada de um envio pendente — e nenhuma das duas
  # passa de novo pelo `poll`. Mutação MH (o publicador ignorando o hook) reprova em `async_publisher_spec`.
  describe '#publicavel? — a ultima palavra antes da mensagem' do
    let(:linha) { cotacao_com_precos(status: 'running') }
    let(:run) do
      origem = linha
      execucao(argumentos: { 'seguradoras' => ['Porto'], described_class::ORIGEM => origem.id }).tap do |execucao|
        execucao.update!(handle: { 'sufixo' => 'placa ABC1D23',
                                   described_class::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => url }] })
      end
    end

    def url
      'https://arquivos.exemplo.test/proposta-8.pdf'
    end

    def entrega
      Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: 'Proposta Porto — placa ABC1D23.pdf',
                                                     legenda: 'Proposta da Porto.', reserva: "Proposta da Porto:\n#{url}").to_h
    end

    def proposta
      no_job('Porto', run: run)
    end

    it 'autoriza enquanto a cotacao de origem vale' do
      expect(proposta.publicavel?(run, entrega)).to be(true)
    end

    it 'recusa a proposta quando a origem foi supersedida depois do poll' do
      run
      cotacao_nova_em_andamento

      expect(proposta.publicavel?(run, entrega)).to be(false)
    end

    it 'recusa a proposta quando uma cotacao nova esta correndo sem preco' do
      linha.update!(status: 'done')
      run
      cotacao_nova_em_andamento

      expect(proposta.publicavel?(run, entrega)).to be(false)
    end

    it 'recusa tambem o link de reserva da mesma proposta' do
      run
      cotacao_nova_em_andamento

      expect(proposta.publicavel?(run, "Proposta da Porto:\n#{url}")).to be(false)
    end

    # A EXPLICAÇÃO SAI: barrar tudo deixaria o cliente em silêncio depois de "já estou buscando".
    it 'deixa passar a explicacao e o fecho do job, mesmo com a origem morta' do
      run
      cotacao_nova_em_andamento

      expect(proposta.publicavel?(run, described_class::SUBSTITUIDA)).to be(true)
      expect(proposta.publicavel?(run, described_class::PARCIAL)).to be(true)
    end
  end

  # O CAMINHO REAL: o `AsyncRunJob` monta a ferramenta sem `delivery`, com os argumentos que o aceite
  # gravou e a conversa da execução. Depois, o publicador baixa o PDF e o anexa com o nome da
  # seguradora, e a cotação fica marcada.
  describe 'pelo job' do
    let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }

    before do
      register_async_tool(described_class)
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('arquivos.exemplo.test').and_return(['93.184.216.34'])
      %w[8 20].each do |codigo|
        stub_request(:get, "https://arquivos.exemplo.test/proposta-#{codigo}.pdf")
          .to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      end
    end

    def passadas(run, quantas)
      quantas.times { |passada| Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, passada) }
    end

    def bot_messages
      conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
    end

    # TRÊS passadas: submeter, entregar, e a que confirma a mensagem e encerra.
    it 'acha a cotacao fixada em start, anexa a proposta em poll e marca a cotacao' do
      # Arrange
      linha = cotacao_com_precos
      run = execucao('Porto')

      # Act
      passadas(run, 3)

      # Assert
      expect(connector).to have_received(:quote_proposal).with(hash_including(insurer_code: '8', quote_id: 'q1')).once
      expect(connector).not_to have_received(:quote_start)
      expect(bot_messages.map(&:content)).to eq(['Proposta da Porto.'])
      expect(bot_messages.sole.attachments.sole.file.filename.to_s).to eq('Proposta Porto — placa ABC1D23.pdf')
      expect(run.reload).to have_attributes(status: 'done', handle: hash_including(described_class::GERADAS => [hash_including('code' => '8')]))
      # A marca fica na cotação, não na execução da proposta: é a cotação que a medida soma.
      expect(run.handle).not_to have_key(cotacao::PROPOSTAS_KEY)
      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(['8'])
    end

    # Duas seguradoras são CINCO passadas, nesta ordem: pede a primeira, entrega a primeira, pede a
    # segunda, entrega a segunda, confirma e encerra. As geradas saem antes das pendentes — é o que
    # faz o arquivo pronto chegar mesmo quando a segunda seguradora está muda (Codex, rodada 2, P2).
    it 'duas seguradoras chegam como dois anexos, em cinco passadas, uma coisa por passada' do
      linha = cotacao_com_precos
      run = execucao('Porto', 'Suhai')

      passadas(run, 5)

      expect(pedidos).to eq(%w[8 20])
      expect(bot_messages.map(&:content)).to eq(['Proposta da Porto.', 'Proposta da Suhai.'])
      expect(bot_messages.map { |mensagem| mensagem.attachments.sole.file.filename.to_s })
        .to eq(['Proposta Porto — placa ABC1D23.pdf', 'Proposta Suhai — placa ABC1D23.pdf'])
      expect(run.reload.status).to eq('done')
      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(%w[20 8])
    end

    # O PRAZO ESTOUROU COM A SEGUNDA SEGURADORA POR PEDIR (Codex, rodada 2, P2): a Porto pronta sai
    # na primeira passada de entrega, e o encerramento por prazo ainda avisa da Suhai. Antes, a
    # execução gastava as passadas pedindo a Suhai e morria publicando só "não consegui".
    it 'com o prazo curto e a segunda seguradora por pedir, a Porto sai e o aviso da Suhai tambem' do
      cotacao_com_precos
      run = execucao('Porto', 'Suhai')

      passadas(run, 2)
      run.update!(expires_at: 1.second.ago)
      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 2)

      expect(pedidos).to eq(['8'])
      expect(bot_messages.map(&:content))
        .to eq(['Proposta da Porto.', 'Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima.',
                described_class::PARCIAL])
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
    end

    # A PUBLICAÇÃO ADIADA NÃO PASSA DE NOVO PELO `poll`: quem a barra é o hook da ferramenta, sob o
    # lock, imediatamente antes de a mensagem existir (rodada 3, P1 do Codex).
    it 'a entrega adiada nao vira mensagem quando a cotacao e refeita antes da publicacao' do
      cotacao_com_precos(status: 'running')
      run = execucao('Porto')
      passadas(run, 1)
      entrega = no_job('Porto', run: run.reload).poll(handle: run.handle, attempt: 1).deliveries.first
      cotacao_nova_em_andamento

      resultado = Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)

      expect(resultado).to be_blocked
      expect(bot_messages).to be_empty
    end

    # Sem origem fixada nos argumentos (execução anterior ao deploy que passou a fixá-la), o job não
    # escolhe uma cotação agora: o cliente lê a recusa própria e pede de novo.
    it 'sem a origem fixada, o cliente le a recusa e nenhuma chamada ao portal sai' do
      run = execucao('Porto')

      passadas(run, 2)

      expect(bot_messages.map(&:content)).to eq([described_class::SEM_ORIGEM])
      expect(connector).not_to have_received(:quote_proposal)
      expect(run.reload.status).to eq('done')
    end

    it 'com a origem supersedida entre o aceite e o start, o cliente le que a cotacao foi refeita' do
      cotacao_com_precos(status: 'running')
      run = execucao('Porto')
      cotacao_nova_em_andamento

      passadas(run, 2)

      expect(bot_messages.map(&:content)).to eq([described_class::SUBSTITUIDA])
      expect(connector).not_to have_received(:quote_proposal)
      expect(run.reload.status).to eq('done')
    end
  end

  describe '.available_for?' do
    it 'segue a porta da cotacao: modulo ligado e conexao pronta' do
      expect(described_class.available_for?(agent)).to be(true)
      expect(described_class.available_for?(agent)).to eq(cotacao.available_for?(agent))

      conexao.update!(status: 'degraded')
      expect(described_class.available_for?(agent)).to be(false)
    end
  end
end
