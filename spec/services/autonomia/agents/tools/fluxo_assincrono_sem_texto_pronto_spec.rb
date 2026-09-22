require 'rails_helper'

# A VARREDURA DA PR C: NENHUM CAMINHO DO FLUXO ASSÍNCRONO GRAVA MENSAGEM PÚBLICA DE TEXTO QUE NÃO VENHA DO MODELO.
#
# Duas metades, e cada uma pega o que a outra não vê:
#
#   - ESTÁTICA: todo ponto do fluxo (motor, publicador, ferramentas, turno de evento, aviso ao atendente) que cria
#     mensagem é conhecido, e cada um só cria o que pode — o publicador, anexo com `content: nil`; o aviso ao
#     atendente, nota com `private: true`; o turno de evento, o texto que o modelo devolveu. Um quarto ponto, ou um
#     desses mudando o que grava, reprova aqui: é assim que a frase pronta voltaria.
#   - DINÂMICA: os caminhos reais do motor (começo, recusa, conclusão, falha, prazo, varredor, a execução que
#     atravessou o deploy com as frases do especialista nos argumentos) rodam, e toda mensagem pública do bot na
#     conversa é um arquivo sem texto. A fala da Lia vem depois, no `EventoJob`, e só dele.
RSpec.describe 'Fluxo assíncrono sem texto pronto' do # rubocop:disable RSpec/DescribeClass
  describe 'estatica' do
    let(:raizes_do_fluxo) { %w[app/services/autonomia/agents/tools app/jobs/autonomia/agents/tools] }
    let(:arquivos_do_turno) do
      %w[app/jobs/autonomia/agents/operate/evento_job.rb app/services/autonomia/agents/operate/aviso_ao_atendente.rb
         app/services/autonomia/agents/operate/responder_ao_evento.rb]
    end
    let(:criadores) { ['MessageBuilder', 'messages.create', 'messages.new', 'messages.build', 'Message.create', 'Message.new'] }

    def arquivos_do_fluxo
      raizes_do_fluxo.flat_map { |raiz| Dir[Rails.root.join(raiz, '**', '*.rb').to_s] }
                     .map { |caminho| Pathname(caminho).relative_path_from(Rails.root).to_s } + arquivos_do_turno
    end

    # -> { caminho => [nó de chamada `Messages::MessageBuilder.new`] }
    def chamadas_ao_builder(caminho)
      achadas = []
      visitar = lambda do |no|
        next unless no.is_a?(Prism::Node)

        achadas << no if no.is_a?(Prism::CallNode) && no.name == :new && no.receiver&.slice == 'Messages::MessageBuilder'
        no.compact_child_nodes.each { |filho| visitar.call(filho) }
      end
      visitar.call(Prism.parse_file(Rails.root.join(caminho).to_s).value)
      achadas
    end

    # O valor do parâmetro `chave` montado dentro do `ActionController::Parameters.new(...)` desta chamada, em texto.
    def parametro(chamada, chave)
      pares_dos_parametros(chamada).find { |par| par.key.respond_to?(:unescaped) && par.key.unescaped == chave.to_s }&.value&.slice
    end

    def pares_dos_parametros(chamada)
      parametros = chamada.arguments.arguments.find { |arg| arg.is_a?(Prism::CallNode) && arg.receiver&.slice == 'ActionController::Parameters' }
      parametros.arguments.arguments.select { |arg| arg.respond_to?(:elements) }.flat_map(&:elements)
    end

    it 'so tres arquivos do fluxo criam mensagem' do
      criam = arquivos_do_fluxo.select { |caminho| criadores.any? { |criador| File.read(Rails.root.join(caminho)).include?(criador) } }

      expect(criam).to contain_exactly('app/services/autonomia/agents/tools/async_publisher.rb',
                                       'app/services/autonomia/agents/operate/aviso_ao_atendente.rb',
                                       'app/services/autonomia/agents/operate/responder_ao_evento.rb')
    end

    it 'o publicador so cria anexo, sem texto' do
      chamada = chamadas_ao_builder('app/services/autonomia/agents/tools/async_publisher.rb').sole

      expect(parametro(chamada, :content)).to eq('nil')
      expect(parametro(chamada, :attachments)).to eq('[corpo.anexo]')
    end

    it 'o aviso ao atendente so cria nota privada' do
      chamada = chamadas_ao_builder('app/services/autonomia/agents/operate/aviso_ao_atendente.rb').sole

      expect(parametro(chamada, :private)).to eq('true')
    end

    it 'o turno de evento so publica o texto que o modelo devolveu' do
      chamada = chamadas_ao_builder('app/services/autonomia/agents/operate/responder_ao_evento.rb').sole

      expect(parametro(chamada, :content)).to eq('text')
      expect(parametro(chamada, :private)).to eq('false')
      entrega = File.read(Rails.root.join('app/services/autonomia/agents/operate/responder_ao_evento.rb'))
      expect(entrega).to include('outcome = classic_deliver(result)')
    end
  end

  describe 'dinamica' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
    let(:agent_bot) { create(:agent_bot, account: account) }
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                       instruction: 'Atenda.')
    end
    let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
    let(:progress) { Autonomia::Agents::Tools::Progress }
    let(:job) { Autonomia::Agents::Tools::AsyncRunJob }
    # As frases que a execução anterior à PR C levava no pedido: nenhuma pode aparecer.
    let(:frases_antigas) { { 'espera' => 'Estou vendo isso.', 'falhou' => 'Não deu.', 'comparativo_legenda' => 'Segue.' } }

    around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

    before { stub_arquivo }

    def execucao(notify_customer: true, expires_at: 3.minutes.from_now)
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: { 'frases_ao_cliente' => frases_antigas },
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: notify_customer, expires_at: expires_at)
      run
    end

    def cenario(tool, expires_at: 3.minutes.from_now, passadas: [0, 1])
      register_async_tool(tool)
      run = execucao(expires_at: expires_at)
      passadas.each { |tentativa| job.new.perform(run.id, tentativa) }
      run
    end

    def mensagens_publicas_do_bot
      Message.where(sender_type: 'AgentBot', private: false)
    end

    it 'em nenhum caminho do motor sai mensagem publica com texto' do
      # Arrange / Act — um cenário por caminho, cada um numa execução própria desta conversa
      cenario(build_async_tool(poll: progress.done(deliveries: [arquivo_de_teste, 'texto que não sai']), resultado: true))
      cenario(build_async_tool(handle: { 'recusa' => 'faltam_dados' }, poll: progress.done(evento: 'falta_dado')))
      cenario(build_async_tool(poll: progress.failed('portal_fora')))
      cenario(build_async_tool(poll: progress.done), expires_at: 1.minute.ago, passadas: [0])
      cenario(build_async_tool(poll: progress.running, closing: [arquivo_de_teste], resultado: true, resta: true))
        .tap { |run| run.update!(expires_at: 10.minutes.ago) }
      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform
      Autonomia::Agents::Tools::AsyncPublishJob.new.perform(Autonomia::Agents::ToolRun.last.id, 'o fecho antigo adiado', 30)

      # Assert — só arquivos, sem texto; e cada caminho disparou o seu evento
      expect(mensagens_publicas_do_bot).to be_present
      expect(mensagens_publicas_do_bot.map { |mensagem| [mensagem.content, mensagem.attachments.size] }.uniq).to eq([[nil, 1]])
      tipos = enqueued_jobs.select { |item| item[:job] == Autonomia::Agents::Operate::EventoJob }.map { |item| item[:args].second }
      expect(tipos).to include('cotacao_comecou', 'concluida', 'falta_dado', 'falhou', 'encerrada_por_prazo')
    end

    it 'o turno de evento e o unico que fala, com a fala do modelo, uma vez por evento' do
      lia_responde('fala da Lia')
      run = cenario(build_async_tool(poll: progress.failed('portal_fora')))

      3.times { rodar_eventos }

      falas = mensagens_publicas_do_bot.where.not(content: nil)
      expect(falas.map(&:content)).to eq(['fala da Lia', 'fala da Lia'])
      expect(falas.map { |mensagem| mensagem.content_attributes['autonomia_evento'] }).to eq(["#{run.id}:cotacao_comecou", "#{run.id}:falhou"])
      expect(Message.all.filter_map(&:content).join).not_to include(*frases_antigas.values)
    end
  end
end
