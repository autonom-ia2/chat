require 'rails_helper'

# #3246b: a Bia fala sozinha quando o pagamento cai (com o voucher logo abaixo) e lembra uma vez antes de o link vencer.
# Cada exemplo cobre um modo de falha: falar duas vezes, mandar dois vouchers, falar por cima de quem atende, gastar
# modelo com a janela fechada, calar quando a IA falha, falar do carrinho errado. Dados fictícios, sem rede.
RSpec.describe Autonomia::Agents::Operate::EventoDaViagemJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:bia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', status: :active, enabled: true,
                                     instruction: 'retrato', config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' },
                                                                       'with_knowledge' => false })
  end
  let(:gerada_em) { 2.hours.ago.utc.change(usec: 0) }
  let(:plano) { { 'codigo' => 'P1', 'nome' => 'Plano Viagem Teste', 'preco_total' => '100.0' } }
  let(:proposta) do
    { 'codigo_do_plano' => 'P1', 'codigo_carrinho' => 987_654, 'link' => 'https://pagamento.universal-assistance.com/p/abc',
      'gerada_em' => gerada_em.iso8601, 'pago_em' => '2026-11-26T11:53:08.773' }
  end
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversation, agent: bia, id_cotacao: 'c-1',
                                               planos: [plano], pedido: { 'idades' => [45] }, proposta: proposta)
  end
  let(:evento) { Autonomia::Agents::Tools::EventoDaViagem }
  let(:voucher) { Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher }
  let(:pago) { evento::PAGAMENTO_CONFIRMADO }
  let(:lembrete) { evento::LEMBRETE }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    Autonomia::Agents::AgentInbox.create!(agent: bia, inbox: inbox, account: account, agent_bot: agent_bot)
    lia_responde('Pagamento confirmado! Seu voucher vai aqui embaixo.')
  end

  after do
    Redis::Alfred.delete(Autonomia::Agents::Operate::TurnoEmCurso.chave(conversation.id))
    Redis::Alfred.delete(Autonomia::Agents::Operate::FalaEmCurso.chave_ocupada(conversation.id))
  end

  def rodar(tipo = pago, *resto, gerada: gerada_em.to_i)
    described_class.new.perform(cotacao.id, tipo, gerada, *resto)
  end

  def marca(tipo = pago) = "viagem:#{cotacao.id}:#{gerada_em.to_i}:#{tipo}"
  def mensagens = conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
  def publicas = mensagens.where(private: false)
  def privadas = mensagens.where(private: true)
  def reagendados = enqueued_jobs.select { |job| job[:job] == described_class }.map { |job| job[:args] }
  def jobs_de_cartoes = enqueued_jobs.select { |job| job[:job] == Autonomia::Agents::Operate::EnviarCartoesJob }

  def sem_modelo
    allow(Autonomia::Agents::Answerer).to receive(:new).and_raise('o modelo nao devia ser chamado')
  end

  def nota(tipo, motivo) = I18n.t("#{Autonomia::Agents::Operate::AvisoDaViagem::NOTAS}.#{tipo}.#{motivo}")

  describe 'pagamento confirmado' do
    it 'fala uma vez, com a marca do evento e o cartão do voucher na âncora, e enfileira o envio do PDF' do
      rodar

      fala = publicas.sole
      expect(fala.content).to eq('Pagamento confirmado! Seu voucher vai aqui embaixo.')
      expect(fala.content_attributes).to include(evento::CHAVE => marca)
      expect(fala.content_attributes).not_to have_key(Autonomia::Agents::Tools::Evento::CHAVE)
      cartao = Autonomia::Agents::Operate::CartoesDoTurno.da_ancora(fala).sole
      expect(cartao).to include('tipo' => voucher::TIPO_DO_CARTAO, 'chave' => cotacao.id.to_s,
                                'token' => "#{marca}:cartao:#{voucher::TIPO_DO_CARTAO}:#{cotacao.id}")
      expect(jobs_de_cartoes.map { |job| job[:args] }).to eq([[fala.id]])
      expect(privadas).to be_empty
    end

    it 'dá ao modelo a nota do sistema com o plano e a data do pagamento, sem o link' do
      rodar

      expect(queries_da_lia.sole).to include('AVISO DO SISTEMA SOBRE O PAGAMENTO', 'Isto não é mensagem da pessoa',
                                             'plano Plano Viagem Teste', 'pago em 26/11')
      expect(queries_da_lia.sole).not_to include('pagamento.universal-assistance.com')
    end

    it 'o retry não fala de novo nem chama o modelo, e não duplica o cartão' do
      rodar
      sem_modelo

      expect { rodar }.not_to raise_error
      expect(publicas.count).to eq(1)
      expect(Autonomia::Agents::Operate::CartoesDoTurno.da_ancora(publicas.sole).size).to eq(1)
    end

    it 'a nova tentativa com a fala já postada reenfileira o cartão do voucher pela âncora, sem falar de novo' do
      rodar
      fala = publicas.sole
      clear_enqueued_jobs
      sem_modelo

      rodar

      expect(publicas.count).to eq(1)
      expect(jobs_de_cartoes.map { |job| job[:args] }).to eq([[fala.id]])
    end

    # O modelo também chama `situacao_do_pagamento` no turno do aviso: o cartão é o mesmo (tipo e cotação), um voucher só.
    it 'o cartão do evento e o da situacao_do_pagamento no mesmo turno viram um voucher só' do
      enable_test_encryption!
      Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: bia, login: 'corretor.teste',
                                                    senha: 's3nha-teste', estado: 'ok')
      stub_request(:get, "#{Autonomia::Seguradoras::Universal::Cliente.base_url}/v1/StatusPagamento/987654")
        .to_return(status: 200, body: { 'statusPagamento' => 'Pago', 'dataPagamento' => '2026-11-26T11:53:08.773' }.to_json)
      allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
        Autonomia::Agents::Tools::Native::SituacaoDoPagamento.new(agent: bia, params: {}, delivery: kwargs[:delivery]).call
        instance_double(Autonomia::Agents::Answerer, answer: resposta_da_lia('Confirmado!'))
      end

      rodar

      expect(Autonomia::Agents::Operate::CartoesDoTurno.da_ancora(publicas.sole).map { |cartao| cartao['tipo'] }).to eq([voucher::TIPO_DO_CARTAO])
      # A marca que a ferramenta gravou é a do próprio aviso: ela não o calou.
      expect(cotacao.reload.proposta[voucher::MARCADO_NO_TURNO]).to eq(marca)
    end

    it 'com o voucher já enviado (a pessoa perguntou antes), não fala' do
      cotacao.update!(proposta: proposta.merge('voucher_enviado_em' => 1.minute.ago.iso8601))
      sem_modelo

      rodar

      expect(mensagens).to be_empty
    end

    it 'a proposta trocada depois do pagamento: nota à equipe só com o carrinho anterior pago, sem os fatos da nova' do
      cotacao
      sem_modelo

      rodar(pago, gerada: gerada_em.to_i - 3600)

      expect(publicas).to be_empty
      expect(privadas.sole.content).to eq(nota(pago, 'carrinho_substituido'))
      expect(privadas.sole.content).not_to include('Plano Viagem Teste')
      expect(jobs_de_cartoes).to be_empty
    end

    it 'a cotação apagada: só log' do
      id = cotacao.id
      cotacao.destroy!

      described_class.new.perform(id, pago, gerada_em.to_i)

      expect(mensagens).to be_empty
    end
  end

  # O cliente perguntou "caiu?" enquanto o aviso esperava a IA: o turno dele conferiu, marcou o voucher (a marca do turno
  # fica na proposta) e respondeu. O aviso confere de novo na hora de postar, sob o lock da conversa, e cala: um
  # "confirmado" e um PDF só.
  describe 'o turno do cliente que confere o pagamento enquanto o aviso espera a IA' do
    let(:turno_do_cliente) do
      Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: Autonomia::Agents::AgentInbox.find_by!(inbox: inbox),
                                             origin_message_id: 4242)
    end

    before do
      enable_test_encryption!
      Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: bia, login: 'corretor.teste',
                                                    senha: 's3nha-teste', estado: 'ok')
      stub_request(:get, "#{Autonomia::Seguradoras::Universal::Cliente.base_url}/v1/StatusPagamento/987654")
        .to_return(status: 200, body: { 'statusPagamento' => 'Pago', 'dataPagamento' => '2026-11-26T11:53:08.773' }.to_json)
    end

    # O modelo do aviso demora; nesse meio-tempo, o turno do cliente roda a ferramenta e o que vier em `depois`.
    def cliente_confere_durante_o_aviso(&depois)
      allow(Autonomia::Agents::Answerer).to receive(:new) do
        Autonomia::Agents::Tools::Native::SituacaoDoPagamento.new(agent: bia, params: {}, delivery: turno_do_cliente).call
        depois&.call
        instance_double(Autonomia::Agents::Answerer, answer: resposta_da_lia('Confirmado pelo aviso!'))
      end
    end

    def mensagem_do_bot(content, atributos)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_bot,
                       content: content, content_attributes: atributos)
    end

    def vouchers = publicas.select { |message| message.content_attributes.to_h.key?(voucher::CHAVE) }

    it 'o voucher marcado pelo cliente e ainda não enviado: o aviso cala na hora de postar e não enfileira cartão' do
      cliente_confere_durante_o_aviso

      rodar

      expect(cotacao.reload.proposta[voucher::MARCADO_NO_TURNO]).to eq('mensagem:4242')
      expect(mensagens).to be_empty
      expect(jobs_de_cartoes).to be_empty
    end

    it 'âncora do cliente, depois o voucher do cliente, e a fala do aviso calada: um PDF só' do
      cliente_confere_durante_o_aviso do
        ancora = mensagem_do_bot('Caiu sim!', Autonomia::Agents::Operate::CartoesDoTurno.marca(turno_do_cliente))
        token = Autonomia::Agents::Operate::CartoesDoTurno.da_ancora(ancora).sole['token']
        mensagem_do_bot(nil, { voucher::CHAVE => cotacao.id, Autonomia::Agents::Operate::CartoesDoTurno::TOKEN => token })
        cotacao.update!(proposta: cotacao.reload.proposta.merge('voucher_enviado_em' => Time.current.iso8601))
      end

      rodar

      expect(publicas.first.content).to eq('Caiu sim!')
      expect(vouchers.size).to eq(1)
      expect(mensagens.select { |message| message.content_attributes.to_h.key?(evento::CHAVE) }).to be_empty
      expect(publicas.map(&:content)).not_to include('Confirmado pelo aviso!')
      expect(jobs_de_cartoes).to be_empty
    end

    it 'com o voucher já marcado pelo cliente antes de o aviso começar, o modelo nem roda' do
      cotacao.update!(proposta: proposta.merge(voucher::MARCADO_NO_TURNO => 'mensagem:4242'))
      sem_modelo

      rodar

      expect(mensagens).to be_empty
    end
  end

  describe 'a janela do canal' do
    before { allow_any_instance_of(Conversation).to receive(:can_reply_automatically?).and_return(false) } # rubocop:disable RSpec/AnyInstance

    it 'fechada no pagamento confirmado: nota dizendo que o voucher não foi enviado, e o modelo não roda' do
      sem_modelo

      rodar

      expect(publicas).to be_empty
      nota_da_janela = privadas.sole
      expect(nota_da_janela.content).to include(nota(pago, 'fora_da_janela'), 'Plano Viagem Teste')
      expect(nota_da_janela.content_attributes).to include(evento::CHAVE => marca)
    end

    it 'fechada com humano no comando: a nota diz que a conversa está com um atendente, não que a janela fechou' do
      conversation.update!(assignee: create(:user, account: account, role: :agent))
      sem_modelo

      rodar

      expect(privadas.sole.content).to include(nota(pago, 'inelegivel'))
      expect(privadas.sole.content).not_to include(nota(pago, 'fora_da_janela'))
    end
  end

  describe 'quem está no comando' do
    let(:atendente) { create(:user, account: account, role: :agent) }

    it 'com humano na conversa: nota com os fatos, sem PDF e sem modelo' do
      conversation.update!(assignee: atendente)
      sem_modelo

      rodar

      expect(publicas).to be_empty
      expect(privadas.sole.content).to include('Plano Viagem Teste', nota(pago, 'inelegivel'))
      expect(jobs_de_cartoes).to be_empty
    end

    it 'com outro agente na caixa: nota, sem modelo' do
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'custom', status: :active,
                                               enabled: true, instruction: 'Atenda.')
      Autonomia::Agents::AgentInbox.where(inbox: inbox).update_all(autonomia_agent_id: outro.id) # rubocop:disable Rails/SkipsModelValidations
      sem_modelo

      rodar

      expect(publicas).to be_empty
      expect(privadas.count).to eq(1)
    end
  end

  describe 'a falha do turno' do
    it 'IA falhou: nova tentativa com espera, nada postado' do
      lia_responde(nil)

      rodar

      expect(mensagens).to be_empty
      expect(reagendados).to eq([[cotacao.id, pago, gerada_em.to_i, 0, 1]])
    end

    it 'falhou duas vezes: escala com nota, nenhuma mensagem pública' do
      lia_responde(nil)
      conversation.update!(ai_assignee: agent_bot, status: :pending)

      rodar(pago, 0, 1)

      expect(publicas).to be_empty
      expect(privadas.sole.content).to include(nota(pago, 'ia_falhou'))
      expect(conversation.reload.status).to eq('open')
      expect(reagendados).to be_empty
    end

    it 'sinal de silêncio: só a nota, sem nova tentativa' do
      lia_responde('conversation_closed_for_now')

      rodar

      expect(publicas).to be_empty
      expect(privadas.sole.content).to include(nota(pago, 'silencio'))
      expect(reagendados).to be_empty
    end
  end

  describe 'o turno do cliente em curso' do
    it 'espera e reagenda, com teto' do
      Autonomia::Agents::Operate::TurnoEmCurso.abrir(conversation.id, 99)
      sem_modelo

      rodar

      expect(mensagens).to be_empty
      expect(reagendados).to eq([[cotacao.id, pago, gerada_em.to_i, 1, 0]])
    end

    it 'no teto, fala assim mesmo' do
      Autonomia::Agents::Operate::TurnoEmCurso.abrir(conversation.id, 99)

      rodar(pago, Autonomia::Agents::Tools::AsyncConfig::MAX_DEPENDENCY_DEFERRALS)

      expect(publicas.count).to eq(1)
    end
  end

  describe 'lembrete' do
    # 26/11/2026 15:00 UTC = 12:00 em São Paulo, 13 h depois da proposta.
    let(:agora) { Time.utc(2026, 11, 26, 15, 0, 0) }
    let(:gerada_em) { agora - 13.hours }

    before do
      travel_to agora
      allow(Crm::Timezone::Resolver).to receive(:new).and_return(instance_double(Crm::Timezone::Resolver,
                                                                                 zone_or_default: ActiveSupport::TimeZone['America/Sao_Paulo']))
      cotacao.update!(proposta: proposta.except('pago_em'))
    end

    it 'fala com até quando o link vale e o link, sem cartão de voucher' do
      lia_responde('Sua proposta ainda está esperando o pagamento.')

      rodar(lembrete)

      fala = publicas.sole
      expect(fala.content_attributes).to include(evento::CHAVE => marca(lembrete))
      expect(Autonomia::Agents::Operate::CartoesDoTurno.da_ancora(fala)).to be_empty
      vence = (gerada_em + 23.hours).in_time_zone(Crm::Timezone::Resolver.new(account: account).zone_or_default)
      expect(queries_da_lia.sole).to include("vale até #{vence.strftime('%d/%m às %H:%M')}",
                                             'link de pagamento: https://pagamento.universal-assistance.com/p/abc')
    end

    it 'janela fechada: só log, nenhuma mensagem' do
      allow_any_instance_of(Conversation).to receive(:can_reply_automatically?).and_return(false) # rubocop:disable RSpec/AnyInstance
      sem_modelo

      rodar(lembrete)

      expect(mensagens).to be_empty
    end

    # A hora conferida de novo na hora de falar: o evento pode ter esperado o turno do cliente, a nova tentativa ou a fila.
    it 'na hora de falar, 23 h depois da proposta, cala' do
      travel_to gerada_em + 23.hours
      sem_modelo

      rodar(lembrete)

      expect(mensagens).to be_empty
    end

    it 'na hora de falar, de noite no fuso da conta, cala' do
      travel_to Time.utc(2026, 11, 27, 0, 30, 0) # 21:30 em São Paulo, 22 h 30 depois da proposta
      sem_modelo

      rodar(lembrete)

      expect(mensagens).to be_empty
    end

    it 'na hora de falar, com uma proposta mais nova na conversa, cala' do
      Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversation, agent: bia, id_cotacao: 'c-2',
                                                 planos: [plano], pedido: { 'idades' => [45] },
                                                 proposta: proposta.merge('codigo_carrinho' => 111_222))
      sem_modelo

      rodar(lembrete)

      expect(mensagens).to be_empty
    end

    it 'falhou duas vezes: só a nota, sem passar a conversa para a equipe' do
      lia_responde(nil)
      conversation.update!(ai_assignee: agent_bot, status: :pending)

      rodar(lembrete, 0, 1)

      expect(publicas).to be_empty
      expect(privadas.sole.content).to include(nota(lembrete, 'ia_falhou'))
      expect(conversation.reload.status).to eq('pending')
      expect(reagendados).to be_empty
    end

    it 'o pagamento que chegou depois da conferência cala o lembrete' do
      cotacao.update!(proposta: proposta)
      sem_modelo

      rodar(lembrete)

      expect(mensagens).to be_empty
    end

    it 'o turno do lembrete recusa gerar proposta' do
      contexto = nil
      allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
        contexto = kwargs[:delivery]
        instance_double(Autonomia::Agents::Answerer, answer: resposta_da_lia('ok'))
      end

      rodar(lembrete)

      expect(contexto).to be_turno_de_evento
      expect(contexto.turno).to eq(marca(lembrete))
    end
  end
end
