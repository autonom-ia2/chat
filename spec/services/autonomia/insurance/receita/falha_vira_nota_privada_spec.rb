require 'rails_helper'

# R20 DA RECEITA DE RAMO: TODA FALHA DA COTAÇÃO CHEGA À EQUIPE EM NOTA PRIVADA.
#
# A Lia fala com o cliente sem motivo, sem recusa e sem processo (regra do Rodrigo, chat#638). Quem atende precisa do
# motivo, e ele só chega por mensagem PRIVADA na conversa, que o cliente não recebe e nenhum modelo lê. O mapa abaixo
# é cada falha da cotação, onde ela nasce e por qual nota chega à equipe; cada uma tem um exemplo que PROVOCA a falha
# pelo código de verdade (só o modelo e o portal são dublados) e confere a nota.
#
# TRÊS ESTADOS:
#   coberta              a nota sai sozinha, quando a falha acontece;
#   coberta_na_passagem  a falha fica guardada e sai na nota do encaminhamento (`NotaDoEncaminhamento`), quando a
#                        Lia passa a conversa à equipe; o texto que a ferramenta devolve manda encaminhar;
#   aberta               não há nota; o exemplo é `pending` com o motivo, e reprova quando alguém fizer a nota, para
#                        o mapa ser atualizado.
module FalhasDaCotacao
  MAPA = {
    'seguradora sem proposta' => { estado: :coberta, nota: 'Tools::NotaInterna com a NotaDaEquipe, no fecho' },
    'passagem à equipe' => { estado: :coberta_na_passagem, nota: 'NotaDoEncaminhamento, com o que falhou nos últimos 30 min' },
    'IA falhou duas vezes' => { estado: :coberta, nota: 'Operate::AvisoAoAtendente#escalar, no segundo turno de evento que falha' },
    'especialista esgota as 6 rodadas sem cotar' => { estado: :coberta, nota: 'Insurance::NotaNaHora, pela RodadasEsgotadas do Runner' },
    'portal fora do ar na abertura (conexão fora)' => { estado: :coberta_na_passagem, nota: 'NotaDoEncaminhamento (conexao_indisponivel)' },
    'tempo esgotado na abertura' => { estado: :coberta, nota: 'Tools::NotaInterna com NotaDaEquipe#nota_do_desfecho (falhou)' },
    'envio sem resposta na abertura' => { estado: :coberta, nota: 'Tools::NotaInterna com NotaDaEquipe#nota_do_desfecho (incerta)' },
    'busca de atividade falha' => { estado: :coberta_na_passagem, nota: 'NotaDoEncaminhamento (busca_de_atividade_indisponivel)' },
    'PDF do comparativo não gerado' => { estado: :coberta,
                                         nota: 'Tools::NotaInterna com NotaDaEquipe#nota_do_desfecho (valores_guardados)' },
    'PDF da proposta de uma seguradora não gerado' => { estado: :coberta, nota: 'Insurance::NotaNaHora, no FALHOU da proposta' },
    'conferência em laço' => { estado: :coberta, nota: 'Insurance::NotaNaHora, pela RodadasEsgotadas (EM_LACO)' }
  }.freeze
  ESTADOS = %i[coberta coberta_na_passagem aberta].freeze

  # AS TRÊS QUE FICARAM ABERTAS NA PRIMEIRA VERSÃO (seis rodadas esgotadas, conferência em laço e proposta que não sai)
  # foram decididas pelo Rodrigo em 25/09/2026 (decisão 3, chat#718): nota privada à equipe NA HORA, sem esperar a
  # passagem (`Insurance::NotaNaHora`). O teto das rodadas continua no núcleo do CRM; quem percebe o esgotamento é o
  # Runner, que conta as rodadas que executa (`Insurance::RodadasEsgotadas`), e só no especialista de cotação.
end

RSpec.describe 'R20: toda falha da cotação chega à equipe em nota privada' do # rubocop:disable RSpec/DescribeClass
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true, 'autonomia_agents_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:motivos) { Autonomia::Agents::Tools::Recusa::MOTIVOS }
  let(:params) { { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'item' => 'Gol', 'vehicle' => { 'plate' => 'TYV8I74' } } }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false',
                      AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    enable_test_encryption!
    agent_inbox
    Autonomia::Agents::Tools::RecusasRecentes.retirar(conversation.id)
  end

  def notas = conversation.messages.reload.where(private: true)
  def publicas_nossas = conversation.messages.reload.where(private: false, message_type: :outgoing)

  def conexao(status = 'ready')
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: status, metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def portal(**respostas)
    connector = instance_double(Autonomia::Insurance::Connector::Mock, **respostas)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
    connector
  end

  def erro(tipo)
    Autonomia::Insurance::Connector::Error.new(tipo, 'portal')
  end

  def execucao(handle: {}, expira: 3.minutes.from_now)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug, arguments: params,
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: expira)
    run.merge_handle!(handle) if handle.present?
    run.reload
  end

  def oferta(code, name, status, texto: nil)
    base = { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status }
    return base.merge('reason' => { 'kind' => 'risco', 'text' => texto }) if texto

    base.merge('premium' => { 'amount' => 2119.18, 'currency' => 'BRL', 'basis' => 'total' })
  end

  def guardado(*ofertas)
    { cotacao::RESULTADO_KEY => Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas) }
  end

  def desfecho(run, tipo)
    format(cotacao::DESFECHOS.fetch(tipo), cotacao: 'auto, Gol', run: run.id)
  end

  # As oito da receita; a do portal na abertura são três caminhos no código, e a do PDF, dois.
  it 'o mapa tem as oito falhas da receita, cada uma com estado, e nota nomeada quando coberta' do
    expect(FalhasDaCotacao::MAPA.keys).to contain_exactly(
      'seguradora sem proposta', 'passagem à equipe', 'IA falhou duas vezes', 'especialista esgota as 6 rodadas sem cotar',
      'portal fora do ar na abertura (conexão fora)', 'tempo esgotado na abertura', 'envio sem resposta na abertura',
      'busca de atividade falha', 'PDF do comparativo não gerado', 'PDF da proposta de uma seguradora não gerado',
      'conferência em laço'
    )
    FalhasDaCotacao::MAPA.each_value do |falha|
      expect(FalhasDaCotacao::ESTADOS).to include(falha[:estado])
      expect(falha[:nota].present?).to eq(falha[:estado] != :aberta)
    end
  end

  describe 'no fecho da execução' do
    before { register_async_tool(cotacao) }

    it 'seguradora sem proposta: a nota leva o que ela escreveu no portal' do
      conexao
      run = execucao(handle: guardado(oferta('19', 'Sancor', 'declined', texto: 'Veículo acima da idade')).merge('quote_id' => 'q:1'))

      Autonomia::Agents::Tools::Encerramento.new(run: run, native: cotacao) { raise 'nada a publicar' }.concluir

      expect(notas.sole.content).to include("- Sancor: #{format(cotacao::RECUSOU, texto: 'Veículo acima da idade')}")
      expect(publicas_nossas).to be_empty
    end

    it 'tempo esgotado na abertura: o prazo acaba antes do primeiro preço, e a nota diz que terminou sem preço' do
      conexao
      run = execucao(expira: 1.minute.ago)

      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 1)

      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
      expect(notas.sole.content).to eq(desfecho(run, 'falhou'))
      expect(publicas_nossas).to be_empty
    end

    it 'envio sem resposta na abertura: o portal fica mudo três vezes, e a nota manda conferir no portal' do
      conexao
      portal(quote_validate: { 'valido' => true, 'problemas' => [] }, vehicle_lookup: { 'plate' => 'TYV8I74', 'vehicle_type' => 'v' })
      allow(Autonomia::Insurance::Connector.client).to receive(:quote_start).and_raise(erro(:timeout))
      run = execucao

      3.times { |tentativa| Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, tentativa) }

      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'envio_incerto')
      expect(notas.sole.content).to eq(desfecho(run, 'incerta'))
      expect(publicas_nossas).to be_empty
    end

    it 'PDF do comparativo não gerado: há preço, o portal não gera o PDF, e a nota diz que ele não chegou' do
      conexao
      portal(quote_proposal: nil)
      allow(Autonomia::Insurance::Connector.client).to receive(:quote_proposal).and_raise(erro(:unavailable))
      stub_const("#{cotacao}::ESPERAS_DO_COMPARATIVO", [])
      run = execucao(handle: guardado(oferta('8', 'Porto Seguro', 'quoted')).merge('quote_id' => 'q:1', cotacao::DELIVERED_KEY => ['8']))

      Autonomia::Agents::Tools::Encerramento.new(run: run, native: cotacao) { raise 'nada a publicar' }.encerrar

      expect(eventos_disparados(run)).to eq(['valores_guardados'])
      expect(notas.sole.content).to eq(desfecho(run, 'valores_guardados'))
      expect(publicas_nossas).to be_empty
    end
  end

  describe 'no turno de evento' do
    before do
      register_async_tool(build_async_tool)
      lia_responde(nil)
      conversation.update!(ai_assignee: agent_bot, status: :pending)
    end

    it 'IA falhou duas vezes: a conversa vai para a equipe, com a nota do evento' do
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)

      Autonomia::Agents::Operate::EventoJob.new.perform(run.id, 'falhou')
      segunda = enqueued_jobs.find { |job| job[:job] == Autonomia::Agents::Operate::EventoJob && job[:args].first == run.id }
      Autonomia::Agents::Operate::EventoJob.new.perform(*segunda[:args])

      expect(notas.sole.content).to include(Autonomia::Agents::Operate::AvisoAoAtendente::MOTIVOS['ia_falhou'])
      expect(publicas_nossas).to be_empty
    end
  end

  # A LIA PASSA A CONVERSA À EQUIPE no mesmo turno em que a ferramenta falhou (o caminho da conversa 7057). O modelo é
  # dublado; a falha acontece de verdade, dentro do turno, pela ferramenta ou pelo especialista.
  describe 'na passagem à equipe' do
    before do
      conversation.update!(assignee_agent_bot_id: agent_bot.id)
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'quero cotar')
    end

    def turno
      Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                             origin_message_id: conversation.messages.incoming.last.id)
    end

    def passar_a_equipe
      resposta = Autonomia::Agents::AnswerResult.new(reply: 'Vou chamar alguém da equipe.', confidence: 0.9,
                                                     handoff: { should: true, reason: 'ai_unavailable' })
      allow(Autonomia::Agents::Answerer).to receive(:new) do
        yield(turno)
        instance_double(Autonomia::Agents::Answerer, answer: resposta)
      end
      Autonomia::Agents::Operate::Responder.new(conversation: conversation, agent_inbox: agent_inbox).perform
    end

    def nota_do_encaminhamento(codigo)
      "#{Autonomia::Agents::NotaDoEncaminhamento::TITULO}\n- #{motivos.fetch(codigo)}"
    end

    it 'passagem à equipe: o especialista caiu, e a nota diz o que a IA não conseguiu' do
      specialist = Autonomia::Agents::Specialist.create!(agent: agent, name: 'Cotação', slug: 'cotacao_auto',
                                                         description: 'cota auto', instruction: 'Você cota.')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_raise(RuntimeError)

      passar_a_equipe { |delivery| Autonomia::Agents::Specialists::Runner.new(specialist: specialist, request: 'cotar', delivery: delivery).call }

      expect(notas.sole.content).to eq(nota_do_encaminhamento('especialista_falhou'))
      expect(publicas_nossas.pluck(:content)).to eq(['Vou chamar alguém da equipe.'])
    end

    it 'portal fora do ar na abertura: a conferência recusa pela conexão, e a nota diz por quê' do
      conexao('offline')
      chamada = { 'name' => cotacao.slug, 'arguments' => params.to_json }

      passar_a_equipe { |delivery| Autonomia::Agents::Tools::Bound.new(agent: agent, native: cotacao).execute(chamada, delivery: delivery) }

      expect(notas.sole.content).to eq(nota_do_encaminhamento('conexao_indisponivel'))
    end

    it 'busca de atividade falha: o portal não responde à busca, e a nota diz qual busca' do
      conexao
      portal(atividade_lookup: nil)
      allow(Autonomia::Insurance::Connector.client).to receive(:atividade_lookup).and_raise(erro(:unavailable))
      busca = { 'termos' => %w[padaria] }

      passar_a_equipe { |delivery| Autonomia::Agents::Tools::Native::AtividadeLookup.new(agent: agent, params: busca, delivery: delivery).call }

      expect(notas.sole.content).to eq(nota_do_encaminhamento('busca_de_atividade_indisponivel'))
    end
  end

  # NA HORA, SEM EXECUÇÃO NEM PASSAGEM (decisão 3, chat#718). O modelo é dublado; a conferência recusa de verdade pelo
  # `precheck` da ferramenta, e o PDF da proposta falha pelo portal dublado.
  describe 'na hora, sem execução nem passagem' do
    let(:lia) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                       enabled: true, instruction: 'Atenda.', config: { 'with_knowledge' => false })
    end
    let(:specialist) do
      Autonomia::Agents::Specialist.create!(agent: lia, name: 'Cotação', slug: 'cotacao_auto', description: 'cota auto',
                                            instruction: 'Você cota.')
    end
    let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 7) }

    # O modelo dublado chama a cotação uma vez por rodada, nas seis, e a conferência recusa cada uma.
    def seis_rodadas_recusadas(recusas, especialista: specialist)
      fila = recusas.dup
      nativa = build_async_tool(slug: 'cotar_teste', precheck: -> { fila.shift })
      allow(especialista).to receive(:tools).and_return([Autonomia::Agents::Tools::Bound.new(agent: especialista.agent, native: nativa)])
      modelo_de_seis_rodadas
      Autonomia::Agents::Specialists::Runner.new(specialist: especialista, request: 'cotar', delivery: delivery).call
    end

    def modelo_de_seis_rodadas
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
      client = instance_double(Crm::Ai::ResponsesClient)
      allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
        6.times { |i| executor.call([{ 'name' => 'cotar_teste', 'arguments' => '{}', 'call_id' => "c#{i}" }]) }
        { text: { resposta: 'Ainda falta um dado.', dados_faltando: [] }.to_json }
      end
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    end

    def esgotou(ramo = 'auto')
      format(Autonomia::Insurance::RodadasEsgotadas::RODADAS, rodadas: 6, ramo: ramo)
    end

    it 'especialista esgota as 6 rodadas sem cotar' do
      saida = seis_rodadas_recusadas(Array.new(6) { |i| "Antes de cotar, corrija o campo #{i}." })

      expect(saida).to end_with(Autonomia::Agents::Specialists::Runner::COTACAO_NAO_ABERTA)
      expect(notas.sole.content).to eq([esgotou, 'Última recusa da conferência: Antes de cotar, corrija o campo 5.'].join("\n"))
      expect(publicas_nossas).to be_empty
    end

    it 'conferência em laço' do
      recusa = 'Antes de cotar, corrija: coverage.assistance24h, 2000 não existe.'
      saida = seis_rodadas_recusadas(Array.new(6, recusa))

      expect(saida).to end_with(Autonomia::Agents::Specialists::Runner::COTACAO_NAO_ABERTA)
      expect(notas.sole.content).to eq([esgotou, format(Autonomia::Insurance::RodadasEsgotadas::EM_LACO, vezes: 6),
                                        "Última recusa da conferência: #{recusa}"].join("\n"))
      expect(publicas_nossas).to be_empty
    end

    it 'o principal chama o especialista de novo no mesmo turno: uma nota só' do
      seis_rodadas_recusadas(Array.new(6, 'Antes de cotar, corrija o CEP.'))
      seis_rodadas_recusadas(Array.new(6, 'Antes de cotar, corrija o CEP.'))

      expect(notas.count).to eq(1)
    end

    it 'cinco rodadas recusadas e a sexta abre: nenhuma nota' do
      seis_rodadas_recusadas(Array.new(5, 'Antes de cotar, corrija o CEP.'))

      expect(Autonomia::Agents::ToolRun.where(slug: 'cotar_teste').count).to eq(1)
      expect(notas).to be_empty
    end

    # SEM REGRESSÃO FORA DA COTAÇÃO: o mesmo esgotamento num especialista de agente que não é o de cotação não deixa nota,
    # e a saída do Runner é a mesma que era.
    it 'especialista de outro tipo de agente esgota as 6 rodadas: nada muda, nenhuma nota' do
      outro = Autonomia::Agents::Specialist.create!(agent: agent, name: 'Agenda', slug: 'agenda', description: 'agenda',
                                                    instruction: 'Você agenda.')

      saida = seis_rodadas_recusadas(Array.new(6, 'Sem horário.'), especialista: outro)

      expect(saida).to eq("Ainda falta um dado. #{Autonomia::Agents::Specialists::Runner::COTACAO_NAO_ABERTA}")
      expect(notas).to be_empty
    end

    # A CHAVE DA NOTA É O TURNO (revisão da chat#718). O turno de evento não tem mensagem de origem, e com ela na chave
    # todo evento da conversa dava a mesma chave: a primeira nota bloqueava todas as seguintes. Os turnos aqui são os que
    # o `Operate::ResponderAoEvento` monta (evento e execução, sem mensagem de origem).
    describe 'uma nota por ocorrência, nenhuma repetida no mesmo turno' do
      let(:proposta) { Autonomia::Agents::Tools::Native::InsuranceQuoteProposal }
      let(:run) { execucao(handle: guardado(oferta('8', 'Porto Seguro', 'quoted')).merge('quote_id' => 'q:1')) }

      before do
        conexao
        portal(quote_proposal: nil)
        allow(Autonomia::Insurance::Connector.client).to receive(:quote_proposal).and_raise(erro(:unavailable))
        run.update!(status: 'done')
      end

      def turno_de_evento(tipo)
        Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, evento: tipo, execucao_do_evento: run)
      end

      def pedir_proposta(turno)
        proposta.new(agent: agent, params: { 'seguradora' => 'Porto Seguro' }, delivery: turno).call
      end

      def esgotar(turno)
        rodadas = Autonomia::Insurance::RodadasEsgotadas.new(specialist: specialist, delivery: turno, rodadas: 6)
        6.times { rodadas.rodada!(['Antes de cotar, corrija o CEP.']) }
        rodadas.avisar!(tentou_cotar: true, abriu: false)
      end

      it 'a proposta falha em dois eventos: duas notas' do
        pedir_proposta(turno_de_evento('concluida'))
        pedir_proposta(turno_de_evento('valores_guardados'))

        expect(notas.count).to eq(2)
      end

      it 'a proposta falha duas vezes no mesmo evento (a nova tentativa do EventoJob monta outro turno igual): uma nota' do
        2.times { pedir_proposta(turno_de_evento('concluida')) }

        expect(notas.count).to eq(1)
      end

      it 'as rodadas se esgotam em dois eventos: duas notas' do
        esgotar(turno_de_evento('concluida'))
        esgotar(turno_de_evento('sem_aceitacao'))

        expect(notas.count).to eq(2)
      end

      it 'as rodadas se esgotam duas vezes no mesmo evento: uma nota' do
        2.times { esgotar(turno_de_evento('concluida')) }

        expect(notas.count).to eq(1)
      end

      it 'um turno de mensagem e um de evento: duas notas' do
        pedir_proposta(delivery)
        pedir_proposta(turno_de_evento('concluida'))

        expect(notas.count).to eq(2)
      end
    end

    it 'PDF da proposta de uma seguradora não gerado' do
      conexao
      portal(quote_proposal: nil)
      allow(Autonomia::Insurance::Connector.client).to receive(:quote_proposal).and_raise(erro(:unavailable))
      execucao(handle: guardado(oferta('8', 'Porto Seguro', 'quoted')).merge('quote_id' => 'q:1')).update!(status: 'done')
      proposta = Autonomia::Agents::Tools::Native::InsuranceQuoteProposal

      ao_modelo = Array.new(2) { proposta.new(agent: agent, params: { 'seguradora' => 'Porto Seguro' }, delivery: delivery).call }

      expect(ao_modelo).to all(include('Não deu para gerar a proposta'))
      expect(notas.sole.content).to eq(format(proposta::NOTA, nome: 'Porto Seguro', motivo: proposta::MOTIVO_DO_PORTAL))
      expect(publicas_nossas).to be_empty
    end
  end
end
