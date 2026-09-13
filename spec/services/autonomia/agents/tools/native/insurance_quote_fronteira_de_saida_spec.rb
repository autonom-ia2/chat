require 'rails_helper'

# A FRONTEIRA DE SAÍDA DA COTAÇÃO (entrega das frases do especialista, 12/09/2026).
#
# Os dois defeitos que este arquivo trava fazem o CLIENTE PERDER PREÇO que a corretora já pagou, e
# os dois nasciam do mesmo erro de ordem: o handle era marcado como entregue ANTES de o texto final
# existir.
#
#   P1-1 — a peneira do `Progress` descartava a entrega inteira ao achar um caminho de campo, e
#          `build_progress` já tinha gravado `entregues` com os códigos das ofertas. Elas nunca mais
#          eram reemitidas, `delivered_count` ficava zero e o cliente lia a frase de falha sobre
#          dezessete seguradoras acionadas.
#   P1-2 — a mesma peneira devolvia nil para a entrega de arquivo, e `PDF_SENT_KEY` já estava
#          gravada: `comparison_pdf` devolvia nil para sempre e o comparativo nunca mais saía.
#
# E o P2 do token: ele era calculado sobre o texto CRU e o publicador o calculava sobre o texto
# APARADO — duas identidades para a mesma entrega, e `resultado_entregue?` nunca casava.
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
  let(:params) { { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'vehicle' => { 'plate' => 'TYV8I74' } } }
  let(:tool) { described_class.new(agent: agent, params: params, run: run) }
  let(:progress) { Autonomia::Agents::Tools::Progress }
  let(:publicada) { Autonomia::Agents::Tools::EntregaPublicada }
  let(:connector) do
    instance_double(Autonomia::Insurance::Connector::Mock,
                    quote_validate: { 'valido' => true, 'problemas' => [] },
                    vehicle_lookup: { 'plate' => 'TYV8I74', 'model' => 'Gol', 'model_year' => 2016, 'vehicle_type' => 'v' })
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def offer(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total' } }
  end

  def resultado(status, offers)
    { 'quote_id' => 'abc:1', 'status' => status, 'offers' => offers }
  end

  def poll(offers, handle: { 'quote_id' => 'abc:1' }, status: 'running')
    allow(connector).to receive(:quote_result).and_return(resultado(status, offers))
    tool.poll(handle: handle, attempt: 1)
  end

  describe 'P1-1 — a entrega com caminho de campo não pode custar os preços' do
    # O NOME DA SEGURADORA VEM DO PORTAL, e é por ele que um identificador entra num texto que é
    # nosso. Antes desta entrega o `Progress` descartava a entrega INTEIRA: o cliente perdia os dois
    # preços, e o handle já dizia que eles tinham saído.
    it 'entrega os precos e redige o identificador que veio do portal' do
      # Arrange / Act
      resultado = poll([offer('43', 'insured.document Seguros', 2050.40), offer('3', 'Mapfre', 2582.76)])

      # Assert
      texto = resultado.deliveries.sole
      expect(texto).to include('R$ 2.050,40', 'R$ 2.582,76')
      expect(texto).not_to include('insured.document')
    end

    # A OUTRA METADE, e é ela que custava dinheiro: o handle só avança sobre as ofertas que de fato
    # entraram no texto que vai sair. Com o texto perdido na fronteira, `entregues` fica como estava
    # e a passada seguinte emite de novo.
    it 'texto que nao sobrevive a fronteira nao avanca o handle, e a passada seguinte reemite' do
      # Arrange — a fronteira recusa o texto composto desta passada
      allow(progress).to receive(:entregavel).and_wrap_original do |original, valor|
        valor.is_a?(String) && valor.include?('Ezze') ? nil : original.call(valor)
      end

      # Act
      perdida = poll([offer('43', 'Ezze', 2050.40)])

      # Assert — nada saiu, e nada foi marcado como entregue
      expect(perdida.deliveries).to be_empty
      expect(perdida.handle[described_class::DELIVERED_KEY]).to be_blank

      # Act 2 — a fronteira volta ao normal e a passada seguinte reemite a mesma oferta
      allow(progress).to receive(:entregavel).and_call_original
      de_novo = poll([offer('43', 'Ezze', 2050.40)], handle: perdida.handle)

      expect(de_novo.deliveries.sole).to include('R$ 2.050,40')
      expect(de_novo.handle[described_class::DELIVERED_KEY]).to eq(['43'])
    end

    # O AVISO DE RENOVAÇÃO SEM BÔNUS VALE POR SAIR UMA VEZ, e a sentinela dele segue a mesma ordem:
    # marcar o aviso como enviado sem o texto ter saído é o aviso perdido para sempre.
    it 'nao marca o aviso como enviado quando o texto nao saiu' do
      allow(progress).to receive(:entregavel).and_return(nil)
      handle = { 'quote_id' => 'abc:1', described_class::SEM_BONUS_KEY => true }

      perdida = poll([offer('43', 'Ezze', 2050.40)], handle: handle)

      expect(perdida.handle[described_class::AVISO_SENT_KEY]).to be_blank
    end
  end

  describe 'P2 — a identidade gravada é a identidade publicada' do
    # O TOKEN NASCIA DO TEXTO CRU e o publicador o calculava sobre o texto que o `Progress` tinha
    # aparado: duas listas de universos diferentes, e `resultado_entregue?` nunca casava — nem o
    # comparativo saía. O travessão no nome da seguradora é o caso que separa os dois textos.
    it 'o token gravado no handle e o token do texto que sai' do
      resultado = poll([offer('43', 'Porto Seguro — Cia de Seguros Gerais', 2050.40)])

      texto = resultado.deliveries.sole
      expect(texto).not_to include('—')
      expect(resultado.handle[described_class::PRECOS_KEY]).to eq([publicada.token_de(run, texto)])
    end

    it 'grava a identidade na linha, e nao so no handle' do
      resultado = poll([offer('43', 'Ezze', 2050.40)])

      expect(run.reload.handle[described_class::PRECOS_KEY])
        .to eq([publicada.token_de(run, resultado.deliveries.sole)])
    end
  end

  describe 'P1-2 — o comparativo que não sai não pode ficar marcado como enviado' do
    before do
      allow(connector).to receive(:quote_proposal).and_return({ 'url' => 'https://arquivos.exemplo.test/c-9.pdf' })
    end

    def fechar(handle)
      poll([offer('43', 'Ezze', 2050.40)], handle: handle, status: 'completed')
    end

    it 'marca o comparativo como enviado quando a entrega existe' do
      resultado = fechar({ 'quote_id' => 'abc:1' })

      expect(resultado.handle[described_class::PDF_SENT_KEY]).to be(true)
      expect(resultado.handle[described_class::COMPARATIVO_KEY]).to be_present
    end

    it 'nao marca quando a entrega de arquivo nao sobrevive a fronteira' do
      # Arrange — a fronteira recusa a entrega de ARQUIVO, e só ela
      allow(progress).to receive(:entregavel).and_wrap_original do |original, valor|
        valor.is_a?(Hash) ? nil : original.call(valor)
      end

      # Act
      resultado = fechar({ 'quote_id' => 'abc:1' })

      # Assert — sem a sentinela, a passada seguinte gera o comparativo de novo
      expect(resultado.handle[described_class::PDF_SENT_KEY]).to be_blank
      expect(resultado.handle[described_class::COMPARATIVO_KEY]).to be_blank
      expect(resultado.deliveries.sole).to include('R$ 2.050,40')
    end

    # A IDENTIDADE DO COMPARATIVO É DA ENTREGA QUE SAI, não da que se pretendia mandar. Quando a URL
    # não cabe na forma de arquivo, o que sai é o texto de reserva — e é o texto DEPURADO dele que o
    # publicador vai carimbar.
    it 'a identidade do comparativo e a da entrega depurada' do
      resultado = fechar({ 'quote_id' => 'abc:1' })

      expect(resultado.handle[described_class::COMPARATIVO_KEY])
        .to eq(publicada.token_de(run, resultado.deliveries.last))
    end
  end

  describe 'a pontuação que chega ao cliente' do
    # DOIS PONTOS NO ITEM DA LISTA (decisão do CEO): o travessão separava o nome do valor.
    it 'separa nome e valor por dois pontos, nunca por travessao' do
      texto = poll([offer('43', 'Ezze', 2050.40)]).deliveries.sole

      expect(texto).to include('• *Ezze*: R$ 2.050,40 no total')
      expect(texto).not_to include('—')
    end

    # E A GUARDA VALE PARA O TEXTO GERADO, não só para a frase do modelo: o nome vem do portal.
    it 'nao deixa travessao do portal chegar ao cliente' do
      texto = poll([offer('43', 'Bradesco — Auto/RE', 2050.40)]).deliveries.sole

      expect(texto).not_to match(/[—–]/)
      expect(texto).to include('Bradesco - Auto/RE')
    end
  end

  describe 'as frases do especialista no caminho real' do
    let(:params) do
      super().merge('frases_ao_cliente' => { 'primeiros_precos' => 'Olha o que já chegou:',
                                             'sem_veiculo' => 'Me manda a placa do carro, por favor.' })
    end

    it 'abre o lote de precos com a frase que o especialista escreveu' do
      texto = poll([offer('43', 'Ezze', 2050.40)]).deliveries.sole

      expect(texto).to start_with("Olha o que já chegou:\n\n• *Ezze*:")
    end

    it 'recusa sem veiculo com a frase que o especialista escreveu' do
      sem_placa = described_class.new(agent: agent, params: params.merge('vehicle' => {}), run: run)

      expect(sem_placa.start['pedido']).to eq('Me manda a placa do carro, por favor.')
    end

    # A LISTA DE RAMOS CONTINUA DO CÓDIGO: o especialista escreve a abertura, e a lista é colada.
    it 'recusa ramo desconhecido com a frase do especialista mais a lista de ramos do codigo' do
      erro = Autonomia::Insurance::Connector::Error.new(:not_implemented, 'sem ramo')
      allow(connector).to receive(:quote_validate).and_raise(erro)
      com_frase = described_class.new(
        agent: agent, params: params.merge('produto' => 'nautico',
                                           'frases_ao_cliente' => { 'ramo_desconhecido' => 'Esse eu não coto por aqui.' }),
        run: run
      )

      expect(com_frase.start['pedido'])
        .to eq("Esse eu não coto por aqui. #{described_class::Recusas::RAMOS_QUE_COTO}")
    end
  end
end
