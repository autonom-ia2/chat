require 'rails_helper'

# A COTAÇÃO FECHA SEM ESPERAR O PORTAL (fatia 1 do PDF rápido, 13/09/2026) — a ferramenta.
#
# O adapter devolve o status geral `partial` para dois estados diferentes: "ainda chegando preço" e
# "portal pronto, algumas recusaram". Com qualquer recusa o portal nunca diz `completed`, e a
# execução só acabava no prazo de 7 minutos, com o PDF junto. Medido em três cotações reais: todas
# as seguradoras tiveram desfecho (preço ou recusa) em 41 s, 98 s e 64 s; o portal só se declarou
# pronto em 188 s, 380 s e 316 s; e 1 de 5 pedidos de PDF voltou 504 do portal.
#
# Aqui a ferramenta como o motor a monta (com a LINHA da execução): QUANDO ela encerra, e o que ela
# faz quando o comparativo não sai. O caminho pelo motor, com publicação e desfecho, está em
# `async_run_job_fecha_sem_esperar_o_portal_spec`.
#
# Os dados são sintéticos; a FORMA das ofertas é a que o `Connector::Http` entrega depois de traduzir
# o adapter.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: {},
                                     scope: { conversation_id: conversation.id })
  end
  let(:params) { { 'cpf' => '111.444.777-35', 'cep' => '01001-000', 'vehicle' => { 'plate' => 'ABC1D23' } } }
  let(:tool) { described_class.new(agent: agent, params: params, run: run) }
  let(:url) { 'https://arquivos.exemplo.test/comparativo-sintetico.pdf' }
  let(:tentativas) { described_class::Comparativo::TENTATIVAS_KEY }
  let(:arquivo) { Autonomia::Agents::Tools::EntregaDeArquivo }
  let(:connector) do
    instance_double(Autonomia::Insurance::Connector::Mock,
                    quote_validate: { 'valido' => true, 'problemas' => [] },
                    vehicle_lookup: { 'plate' => 'ABC1D23', 'model' => 'Gol', 'model_year' => 2016, 'vehicle_type' => 'v' })
  end
  # Três seguradoras, cada uma com um desfecho diferente — o desenho da cotação real, em miniatura.
  let(:com_desfecho) { [oferta('8', 'quoted', 2119.18), oferta('47', 'declined'), oferta('11', 'auth_required')] }

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    allow(connector).to receive(:quote_proposal).and_return({ 'url' => url })
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def oferta(code, status, amount = nil)
    base = { 'insurer' => { 'code' => code, 'name' => "Seguradora #{code}" }, 'status' => status }
    return base unless amount

    base.merge('premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' })
  end

  def consultar(status, ofertas, handle)
    allow(connector).to receive(:quote_result).and_return({ 'quote_id' => 'abc:1', 'status' => status, 'offers' => ofertas })
    tool.poll(handle: handle, attempt: 5)
  end

  # O handle depois de uma leitura ANTERIOR que listou estas seguradoras, todas com desfecho: a lista de
  # acionadas e a leitura assentada são gravadas pela ferramenta em toda consulta.
  def depois_de_uma_leitura(*codigos)
    { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => [], described_class::ACIONADAS_KEY => codigos,
      described_class::LEITURA_ASSENTADA_KEY => codigos.sort }
  end

  def pdf_de(progresso)
    arquivo.de(progresso.deliveries.last)
  end

  describe 'quando a cotação encerra' do
    it 'encerra com o portal ainda partial quando toda seguradora ja tem desfecho, e entrega o comparativo' do
      # Act
      progresso = consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11'))

      # Assert
      expect(progresso).to be_done
      expect(progresso.deliveries.first).to include('R$ 2.119,18')
      expect(pdf_de(progresso).url).to eq(url)
      expect(progresso.handle[described_class::FECHADO_KEY]).to be(true)
    end

    # A PRIMEIRA LEITURA NÃO ENCERRA: a lista precisa se repetir, com desfecho, em duas leituras seguidas.
    # O custo é um intervalo de consulta depois do último desfecho.
    it 'nao encerra na primeira leitura, mesmo com todas com desfecho' do
      progresso = consultar('partial', com_desfecho, { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => [] })

      expect(progresso).to be_running
      expect(progresso.deliveries.sole).to include('R$ 2.119,18')
      expect(progresso.handle[described_class::FECHADO_KEY]).to be_blank
      expect(connector).not_to have_received(:quote_proposal)
    end

    # O CÁLCULO CUJOS RESULTADOS VIERAM TODOS COM ERRO, e o portal ainda aberto: o adapter o devolve
    # `running` (`toOffer`, sem prêmio escolhível e sem `calc.erros`). Ele adia o encerramento até o
    # portal ficar pronto, quando a mesma oferta passa a `error` — e a cotação encerra na leitura seguinte,
    # que repete a lista com desfecho.
    it 'a seguradora running adia o encerramento ate o portal ficar pronto, quando ela vira error' do
      # Arrange / Act 1 — o portal ainda aberto
      enquanto = consultar('partial', com_desfecho + [oferta('19', 'running')], depois_de_uma_leitura('8', '47', '11', '19'))

      # Assert 1
      expect(enquanto).to be_running
      expect(connector).not_to have_received(:quote_proposal)

      # Act 2 — o portal declara o negócio pronto; a primeira leitura com todas com desfecho
      pronto = consultar('partial', com_desfecho + [oferta('19', 'error')], enquanto.handle)
      expect(pronto).to be_running

      # Act 3 — a mesma lista, de novo
      fechada = consultar('partial', com_desfecho + [oferta('19', 'error')], pronto.handle)

      # Assert — os preços já tinham saído; sai o comparativo
      expect(fechada).to be_done
      expect(fechada.deliveries.size).to eq(1)
      expect(pdf_de(fechada).url).to eq(url)
    end

    it 'nao encerra quando a leitura perdeu uma seguradora que outra leitura ja tinha listado' do
      progresso = consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11', '19'))

      expect(progresso).to be_running
      expect(connector).not_to have_received(:quote_proposal)
    end

    # TODAS RECUSARAM, com o negócio ainda aberto: o adapter diz `running` no geral (nenhum preço), e
    # antes desta fatia a execução esperava o prazo inteiro para dizer a frase de falha.
    it 'com todas recusando, encerra sem comparativo' do
      progresso = consultar('running', [oferta('47', 'declined'), oferta('11', 'auth_required')],
                            depois_de_uma_leitura('47', '11'))

      expect(progresso).to be_done
      expect(progresso.deliveries).to be_empty
      expect(connector).not_to have_received(:quote_proposal)
    end
  end

  describe 'quando o comparativo não sai' do
    let(:portal_fora) { Autonomia::Insurance::Connector::Error.new(:timeout, 'connector timeout em /v1/agger/quote/proposal') }

    it 'o comparativo que o portal nao gera volta running e sai na passada seguinte' do
      # Arrange / Act 1 — o pedido de PDF volta 504
      allow(connector).to receive(:quote_proposal).and_raise(portal_fora)
      primeira = consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11'))

      # Assert 1 — os preços saem; o fechamento do portal fica gravado; é a primeira tentativa
      expect(primeira).to be_running
      expect(primeira.deliveries.sole).to include('R$ 2.119,18')
      expect(primeira.handle).to include(described_class::FECHADO_KEY => true, tentativas => 1)

      # Act 2 — o portal responde
      allow(connector).to receive(:quote_proposal).and_return({ 'url' => url })
      segunda = consultar('partial', com_desfecho, primeira.handle)

      # Assert 2 — só o comparativo, sem repetir os preços
      expect(segunda).to be_done
      expect(pdf_de(segunda).url).to eq(url)
      expect(segunda.deliveries.size).to eq(1)
      expect(segunda.handle[tentativas]).to eq(2)
    end

    # O TETO É DE TRÊS PEDIDOS AO PORTAL. Esgotado, segue o comportamento de antes desta fatia: a
    # cotação conclui sem comparativo. E a passada que viesse depois não pede de novo.
    it 'esgotado o teto de tres tentativas, conclui sem comparativo e nao pede mais' do
      # Arrange
      allow(connector).to receive(:quote_proposal).and_raise(portal_fora)

      # Act
      primeira = consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11'))
      segunda = consultar('partial', com_desfecho, primeira.handle)
      terceira = consultar('partial', com_desfecho, segunda.handle)
      depois = consultar('partial', com_desfecho, terceira.handle)

      # Assert
      expect([primeira, segunda, terceira, depois].map(&:status)).to eq(%i[running running done done])
      expect(terceira.deliveries).to be_empty
      expect(terceira.handle[tentativas]).to eq(described_class::Comparativo::TETO_DE_TENTATIVAS)
      expect(connector).to have_received(:quote_proposal).exactly(3).times
    end

    # O DOWNLOAD É DO PUBLICADOR, depois da passada: quando ele falha, a entrega de arquivo não é
    # ACEITA e o motor não encerra. A passada seguinte vê o comparativo emitido e não aceito, e pede
    # outro ao portal. O aceito não se pede de novo.
    it 'o comparativo emitido que o publicador nao aceitou e gerado de novo; o aceito nao' do
      # Arrange / Act 1 — emitido, e o publicador não o assumiu
      emitido = consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11'))
      expect(emitido).to be_done

      # Act 2
      de_novo = consultar('partial', com_desfecho, emitido.handle)

      # Assert 2 — e a emissão NÃO grava a sentinela de comparativo enviado (rodada 2)
      expect(pdf_de(de_novo).url).to eq(url)
      expect(connector).to have_received(:quote_proposal).twice
      expect([emitido, de_novo].map { |progresso| progresso.handle[described_class::PDF_SENT_KEY] }).to all(be_blank)

      # Act 3 — agora o publicador aceita
      Autonomia::Agents::Tools::EntregaAceita.registrar(
        run, de_novo.deliveries.last, Autonomia::Agents::Tools::AsyncPublisher::Result.new(status: :published)
      )
      aceito = consultar('partial', com_desfecho, de_novo.handle)

      # Assert 3 — a sentinela é gravada na passada que encontra o comparativo assumido
      expect(aceito).to have_attributes(status: :done, deliveries: [])
      expect(connector).to have_received(:quote_proposal).twice
      expect(aceito.handle[described_class::PDF_SENT_KEY]).to be(true)
    end

    # CADA PEDIDO AO PORTAL DEVOLVE UMA URL DIFERENTE (medido em 13/09/2026), e com ela uma identidade
    # diferente. O comparativo emitido cuja MENSAGEM já está na conversa — o publicador a criou e o
    # envio ao canal ficou pendente, o que ele devolve como `blocked` — não é pedido de novo: o
    # segundo pedido viraria um segundo PDF.
    it 'o comparativo emitido cuja mensagem ja esta na conversa nao e pedido de novo, mesmo sem aceite' do
      # Arrange — emitido, sem aceite, e a mensagem dele na conversa com a pendência de envio
      emitido = consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11'))
      token = emitido.handle[described_class::COMPARATIVO_KEY]
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: create(:agent_bot, account: account), content: 'Comparativo com todas as opções.',
                       content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => token,
                                             'autonomia_envio_pendente' => true })

      # Act
      depois = consultar('partial', com_desfecho, emitido.handle)

      # Assert
      expect(depois).to be_done
      expect(depois.deliveries).to be_empty
      expect(connector).to have_received(:quote_proposal).once
    end

    # A URL QUE A FORMA DE ARQUIVO RECUSA (sem https) não vira mais o texto com o link: é um
    # comparativo que não saiu, e volta à regra de nova tentativa. `completed` de propósito: é o status
    # em que a versão anterior já fechava, e mandava o link em texto.
    it 'a URL que a forma de arquivo recusa conta como comparativo que nao saiu, e o link nao sai' do
      allow(connector).to receive(:quote_proposal).and_return({ 'url' => 'http://arquivos.exemplo.test/c.pdf' })

      progresso = consultar('completed', com_desfecho, depois_de_uma_leitura('8', '47', '11'))

      expect(progresso).to be_running
      expect(progresso.deliveries.join).not_to include('arquivos.exemplo.test')
      expect(progresso.handle[described_class::PDF_SENT_KEY]).to be_blank
    end

    # O LINK DO PORTAL NÃO VIAJA COMO TEXTO DE CLIENTE: a URL fica só no campo `url`, de onde o
    # publicador baixa. A reserva continua na forma (a chave `comparativo_reserva` do pedido não mudou),
    # sem o link.
    it 'a reserva da entrega de arquivo nao carrega o link' do
      entrega = pdf_de(consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11')))

      expect(entrega.reserva).to be_present
      expect(entrega.reserva).not_to include(url)
      expect(entrega.legenda).not_to include(url)
    end

    # A PASSADA QUE DEVOLVE `done` MARCA O HANDLE, e a que volta `running` para nova tentativa não
    # marca. É por essa marca que o varredor sabe, numa linha que continua viva, que sobrou o desfecho.
    it 'marca a conclusao na passada que devolve done, e nao na que volta para nova tentativa' do
      allow(connector).to receive(:quote_proposal).and_raise(portal_fora)
      tentativa = consultar('partial', com_desfecho, depois_de_uma_leitura('8', '47', '11'))
      allow(connector).to receive(:quote_proposal).and_return({ 'url' => url })
      concluida = consultar('partial', com_desfecho, tentativa.handle)

      expect(tentativa.handle).not_to have_key(described_class::CONCLUSAO_KEY)
      expect(concluida.handle[described_class::CONCLUSAO_KEY]).to be(true)
    end

    it 'afirma sobra quando a ferramenta ja devolveu done e a linha continua viva' do
      handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['8'],
                 described_class::FECHADO_KEY => true, tentativas => described_class::Comparativo::TETO_DE_TENTATIVAS }

      expect(tool.resta_entregar?(handle)).to be(false)
      expect(tool.resta_entregar?(handle.merge(described_class::CONCLUSAO_KEY => true))).to be(true)
    end

    # O VARREDOR PERGUNTA SE SOBROU ALGO antes de dizer o fecho. Com o portal fechado e o comparativo
    # ainda por tentar, sobrou; esgotado o teto sem comparativo, não sobra mais nada a chegar.
    it 'afirma sobra enquanto o comparativo ainda sera tentado, e nao depois do teto' do
      handle = { 'quote_id' => 'abc:1', described_class::DELIVERED_KEY => ['8'],
                 described_class::FECHADO_KEY => true, tentativas => 1 }

      expect(tool.resta_entregar?(handle)).to be(true)
      expect(tool.resta_entregar?(handle.merge(tentativas => described_class::Comparativo::TETO_DE_TENTATIVAS))).to be(false)
    end
  end
end
