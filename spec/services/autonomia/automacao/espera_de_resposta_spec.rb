require 'rails_helper'

# #2931, #2935 e #2936 (épico #2414): os passos que perguntam e esperam a resposta, no motor. Um mecanismo só para os
# três (EsperaDeResposta): pergunta, espera até o prazo e segue pelo galho da resposta, ou pelo galho "sem resposta".
# A IA (pesquisa e reunião) é a da OpenAI com stub: nada pago.
RSpec.describe Autonomia::Automacao::EsperaDeResposta, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:gerente) { create(:user, account: account, role: :administrator, name: 'Gerente Ana') }
  let(:ana) { create(:contact, account: account, name: 'Ana') }
  let(:conversa) { create(:conversation, account: account, contact: ana, status: :open) }
  let(:respostas_da_ia) { [] }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_ia', 'automacao_passos_novos')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
  end

  after { Current.reset }

  def ia_responde(*saidas)
    fila = saidas.dup
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      respostas_da_ia << JSON.parse(request.body)
      atual = fila.size > 1 ? fila.shift : fila.first
      payload = { id: "resp_#{respostas_da_ia.size}", output_text: atual.to_json, usage: { input_tokens: 500, output_tokens: 50 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def depois(id) = esperar_passo(id, 1, 'horas')

  def aprovacao(quem = { 'de' => 'pessoa', 'id' => gerente.id })
    { 'id' => 'aprova', 'tipo' => 'pedir_aprovacao', 'quem' => quem, 'pergunta' => ['Posso dar 12% para ', { '$valor' => 'contato.nome' }, '?'],
      'prazo' => { 'valor' => 1, 'unidade' => 'dias' }, 'aprovado' => [depois('se_aprovou')], 'recusado' => [depois('se_recusou')],
      'ninguem_respondeu' => [depois('ninguem')] }
  end

  def pesquisa(extra = {})
    { 'id' => 'nota', 'tipo' => 'pesquisa_nota', 'pergunta' => 'De 0 a 10, que nota você dá?', 'baixa_ate' => 6, 'alta_desde' => 9,
      'intervalo_dias' => 30, 'espera' => { 'valor' => 2, 'unidade' => 'dias' }, 'nota_baixa' => [depois('baixa')],
      'nota_media' => [depois('media')], 'nota_alta' => [depois('alta')], 'nao_respondeu' => [depois('calado')] }.merge(extra)
  end

  def rodar(passos)
    definicao = automacao_ligada(account, admin, passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }.reload
  end

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  def cliente_escreve(texto)
    mensagem = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: texto)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  def pedido(execucao) = Autonomia::Automacao::Registro.find_by(execucao: execucao, motivo: described_class::ESPERANDO)

  describe 'Pedir aprovação (#2931)' do
    it 'pede a quem foi escolhido, avisa no sino e, aprovado, segue pelo galho "aprovado"', :aggregate_failures do
      execucao = rodar([aprovacao])

      expect(execucao.estado).to eq('esperando')
      expect(pedido(execucao).dados['para']).to eq([gerente.id])
      aviso = Notification.find_by(user: gerente, notification_type: 'automacao_aprovacao')
      expect(aviso.primary_actor).to eq(pedido(execucao))
      expect(aviso.push_event_data[:primary_actor]).to include(name: execucao.automacao.nome)

      resposta = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::PedidosDeAprovacao.responder!(pedido(execucao), gerente, aprovado: true)
      end

      expect(resposta).to eq(:ok)
      expect(registros(execucao.reload)).to include(['aprova', 'ok', nil], ['se_aprovou', 'ok', nil])
      decidido = Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'aprova', resultado: 'ok').last
      expect(decidido.dados).to include('ramo' => 'aprovado', 'por_nome' => 'Gerente Ana')
    end

    it 'recusado com motivo: o galho "recusado", com o motivo no registro; a segunda resposta não vale', :aggregate_failures do
      execucao = rodar([aprovacao])
      pedido = pedido(execucao)

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::PedidosDeAprovacao.responder!(pedido, gerente, aprovado: false, motivo: 'Passou do combinado')
      end

      expect(Autonomia::Automacao::PedidosDeAprovacao.responder!(pedido.reload, admin, aprovado: true)).to eq(:ja_respondido)
      expect(registros(execucao.reload).map(&:first)).to include('se_recusou')
      expect(registros(execucao).map(&:first)).not_to include('se_aprovou')
      decidido = Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'aprova', resultado: 'ok').last
      expect(decidido.dados).to include('ramo' => 'recusado', 'motivo_da_recusa' => 'Passou do combinado')
    end

    it 'no prazo sem resposta, fecha o pedido e segue por "ninguém respondeu"; a resposta atrasada é recusada', :aggregate_failures do
      execucao = rodar([aprovacao])
      pedido = pedido(execucao)

      travel 25.hours do
        varrer
        expect(Autonomia::Automacao::PedidosDeAprovacao.responder!(pedido.reload, gerente, aprovado: true)).to eq(:fora_do_prazo)
      end

      expect(registros(execucao.reload)).to include(%w[aprova pulado prazo_vencido], ['ninguem', 'ok', nil])
      expect(pedido.reload.dados['fechado']).to be(true)
    end

    it 'ninguém que vê a conversa pode aprovar: segue na hora por "ninguém respondeu", sem aviso', :aggregate_failures do
      fora = create(:user, account: account, role: :agent, name: 'Sem caixa')

      execucao = rodar([aprovacao({ 'de' => 'pessoa', 'id' => fora.id })])

      expect(registros(execucao)).to include(%w[aprova pulado sem_quem_aprove], ['ninguem', 'ok', nil])
      expect(Notification.where(notification_type: 'automacao_aprovacao')).to be_empty
    end
  end

  describe 'Pesquisa de satisfação (#2936)' do
    it 'pergunta com as notas, a IA entende "nota 9, mas demorou" e segue pela nota alta; a nota fica no contato', :aggregate_failures do
      ia_responde({ 'nota' => 9, 'comentario' => 'Demorou um pouco' })
      execucao = rodar([pesquisa])

      expect(execucao.estado).to eq('esperando')
      expect(conversa.messages.outgoing.last.content).to eq('De 0 a 10, que nota você dá?')

      cliente_escreve('nota 9, mas demorou')

      expect(registros(execucao.reload).map(&:first)).to include('alta')
      expect(respostas_da_ia.last['input'].to_json).to include('nota 9, mas demorou')
      lida = ana.reload.additional_attributes
      expect(lida['pesquisa_satisfacao']).to include('nota' => 9, 'automacao_id' => execucao.automacao_id)
      expect(lida.dig('pesquisas', execucao.automacao_id.to_s, 'nota')).to eq(9)
    end

    it 'resposta sem nota clara: espera a próxima, até o prazo; vencido, "se o cliente não responder"', :aggregate_failures do
      ia_responde({ 'nota' => nil, 'comentario' => '' })
      execucao = rodar([pesquisa])

      cliente_escreve('depois eu vejo')

      expect(execucao.reload.estado).to eq('esperando')
      expect(registros(execucao).map(&:third)).to include(described_class::AMBIGUA)

      travel(49.hours) { varrer }

      expect(registros(execucao.reload)).to include(%w[nota pulado prazo_vencido], ['calado', 'ok', nil])
    end

    it 'não pergunta de novo antes do intervalo: pula e segue, sem mandar nada', :aggregate_failures do
      ana.update!(additional_attributes: { 'pesquisa_perguntada_em' => 3.days.ago.iso8601 })

      execucao = rodar([pesquisa, depois('seguinte')])

      expect(registros(execucao)).to include(%w[nota pulado pesquisa_recente], ['seguinte', 'ok', nil])
      expect(conversa.messages.outgoing).to be_empty
    end
  end

  describe 'a flag dos passos novos (rollback)' do
    it 'desligada no meio da espera, a execução para ali, sem seguir nenhum galho', :aggregate_failures do
      execucao = rodar([aprovacao])
      account.disable_features!('automacao_passos_novos')

      travel(25.hours) { varrer }

      expect(execucao.reload.estado).to eq('parada')
      expect(registros(execucao).last).to eq(%w[aprova pulado passos_novos_desligados])
    end
  end

  describe 'Marcar reunião pela conversa (#2935)' do
    around do |example|
      with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { example.run }
    end

    let(:world) { build_booking_world(account: account) }
    let(:ana) { world.contact }

    def reuniao
      { 'id' => 'reuniao', 'tipo' => 'marcar_reuniao', 'com' => { 'de' => 'pessoa', 'id' => world.host.id }, 'duracao' => 30,
        'convite' => 'Posso te ligar em um destes horários?', 'espera' => { 'valor' => 1, 'unidade' => 'dias' },
        'outro_horario' => [depois('outro')], 'nao_respondeu' => [depois('calado')] }
    end

    def oferecidos = Autonomia::Automacao::AgendaDaReuniao.new(account, world.host, 30).horarios

    before do
      travel_to Time.utc(2026, 11, 16, 11, 0, 0)
      account.enable_features!('crm_booking_v2')
      create(:inbox_member, user: world.host, inbox: conversa.inbox)
    end

    it 'oferece os 3 horários, a IA entende a escolha e a reunião fica marcada', :aggregate_failures do
      horarios = oferecidos
      expect(horarios.size).to eq(3)
      ia_responde({ 'escolha' => '2' })
      execucao = rodar([reuniao, depois('seguinte')])

      expect(pedido(execucao).dados['horarios']).to eq(horarios.map(&:iso8601))
      cliente_escreve('pode ser o segundo')

      reuniao = Crm::Meeting.where(account: account).order(:id).last
      expect(reuniao.starts_at).to eq(horarios[1])
      expect(registros(execucao.reload)).to include(['reuniao', 'ok', nil], ['seguinte', 'ok', nil])
    end

    it 'o horário escolhido foi tomado no meio (a trava da agenda): segue por "outro horário"', :aggregate_failures do
      horarios = oferecidos
      ia_responde({ 'escolha' => '1' })
      execucao = rodar([reuniao])
      create_internal_meeting(world: world, starts_at: horarios.first)

      cliente_escreve('o primeiro')

      expect(registros(execucao.reload)).to include(%w[reuniao pulado horario_ocupado], ['outro', 'ok', nil])
    end

    it 'o cliente pede outro dia: segue por "outro horário", sem marcar', :aggregate_failures do
      ia_responde({ 'escolha' => 'outro_horario' })
      execucao = rodar([reuniao])

      expect { cliente_escreve('nenhum desses, pode ser semana que vem?') }.not_to change(Crm::Meeting, :count)
      expect(registros(execucao.reload).map(&:first)).to include('outro')
    end

    it 'a resposta que não deixa claro o horário: não marca e continua esperando a próxima', :aggregate_failures do
      ia_responde({ 'escolha' => 'nenhum' })
      execucao = rodar([reuniao])

      expect { cliente_escreve('talvez, vou ver aqui') }.not_to change(Crm::Meeting, :count)
      expect(execucao.reload.estado).to eq('esperando')
      expect(registros(execucao).map(&:first)).not_to include('outro', 'calado')
    end

    it 'sem nenhum horário livre: não manda o convite e segue por "outro horário"', :aggregate_failures do
      allow(Autonomia::Automacao::AgendaDaReuniao).to receive(:new).and_wrap_original do |original, *argumentos|
        original.call(*argumentos).tap { |agenda| allow(agenda).to receive(:horarios).and_return([]) }
      end

      execucao = nil
      expect { execucao = rodar([reuniao]) }.not_to change(Message.outgoing, :count)
      expect(registros(execucao)).to include(%w[reuniao pulado sem_horario], ['outro', 'ok', nil])
    end
  end
end
