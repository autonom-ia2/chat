require 'rails_helper'

# #3246b: a conferência automática de uma proposta. Cada exemplo cobre um modo de falha: avisar duas vezes, lembrar
# fora de hora ou depois de o link vencer, chamar a Universal com a porta fechada, perder o aviso quando a fila falha.
# Dados fictícios; a Universal responde pelo WebMock.
RSpec.describe Autonomia::Agents::Contratados::ConferirPagamentoJob, type: :job do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:bia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', status: :active, enabled: true,
                                     instruction: 'retrato', config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  # 26/11/2026 15:00 UTC = 12:00 em São Paulo.
  let(:agora) { Time.utc(2026, 11, 26, 15, 0, 0) }
  let(:gerada_em) { agora - 13.hours }
  let(:proposta) do
    { 'codigo_do_plano' => 'P1', 'codigo_carrinho' => 987_654, 'link' => 'https://pagamento.universal-assistance.com/p/abc',
      'gerada_em' => gerada_em.iso8601 }
  end
  let!(:cotacao) { cotacao_com(proposta) }
  let(:evento) { Autonomia::Agents::Tools::EventoDaViagem }
  let(:situacao) { Autonomia::Agents::Tools::Native::SituacaoDoPagamento }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    travel_to agora
    enable_test_encryption!
    allow(Crm::Timezone::Resolver).to receive(:new).and_return(instance_double(Crm::Timezone::Resolver,
                                                                               zone_or_default: ActiveSupport::TimeZone['America/Sao_Paulo']))
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: bia, login: 'corretor.teste', senha: 's3nha-teste',
                                                  estado: 'ok')
    allow(situacao).to receive(:available_for?).and_return(true)
  end

  def cotacao_com(guardada)
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: bia, id_cotacao: 'c-1',
                                               planos: [], pedido: { 'idades' => [45] }, proposta: guardada)
  end

  def universal(status, data: nil)
    stub_request(:get, "#{base}/v1/StatusPagamento/987654")
      .to_return(status: 200, body: { 'statusPagamento' => status, 'dataPagamento' => data }.to_json)
  end

  def conferir(alvo = cotacao, gerada: gerada_em.to_i)
    described_class.new.perform(alvo.id, gerada)
  end

  def eventos
    enqueued_jobs.select { |job| job[:job] == Autonomia::Agents::Operate::EventoDaViagemJob }.map { |job| job[:args] }
  end

  describe 'pago' do
    it 'grava pago_em e aviso_pago_em e enfileira o pagamento_confirmado uma vez só' do
      universal('Pago', data: '2026-11-26T11:53:08.773')

      2.times { conferir }

      expect(cotacao.reload.proposta).to include('pago_em' => '2026-11-26T11:53:08.773', 'aviso_pago_em' => agora.iso8601,
                                                 'conferencias' => 2)
      expect(eventos).to eq([[cotacao.id, evento::PAGAMENTO_CONFIRMADO, gerada_em.to_i]])
    end

    it 'com pago_em já gravado pela ferramenta (a pessoa perguntou), não dispara' do
      cotacao.update!(proposta: proposta.merge('pago_em' => '2026-11-26T11:00:00'))
      universal('Pago')

      conferir

      expect(eventos).to be_empty
      expect(cotacao.reload.proposta).not_to have_key('aviso_pago_em')
    end

    it 'com o voucher já enviado, não dispara' do
      cotacao.update!(proposta: proposta.merge('voucher_enviado_em' => 1.hour.ago.iso8601))
      universal('Pago')

      conferir

      expect(eventos).to be_empty
    end

    it 'a fila que levanta desfaz as duas chaves, e o erro sobe' do
      universal('Pago')
      allow(Autonomia::Agents::Operate::EventoDaViagemJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError)

      expect { conferir }.to raise_error(ActiveJob::EnqueueError)

      expect(cotacao.reload.proposta.keys).not_to include('pago_em', 'aviso_pago_em')
      expect(cotacao.proposta['conferencias']).to eq(1)
    end

    it 'a fila que falha não desfaz quando o voucher saiu nesse meio-tempo, nem o valor que outra execução gravou' do
      universal('Pago', data: '2026-11-26T11:53:08.773')
      allow(Autonomia::Agents::Operate::EventoDaViagemJob).to receive(:perform_later) do
        cotacao.update!(proposta: cotacao.reload.proposta.merge('voucher_enviado_em' => agora.iso8601))
        false
      end

      conferir

      expect(cotacao.reload.proposta).to include('pago_em' => '2026-11-26T11:53:08.773', 'aviso_pago_em' => agora.iso8601)
    end

    it 'a fila que falha só desfaz a chave que ainda tem o valor desta execução' do
      universal('Pago', data: '2026-11-26T11:53:08.773')
      allow(Autonomia::Agents::Operate::EventoDaViagemJob).to receive(:perform_later) do
        cotacao.update!(proposta: cotacao.reload.proposta.merge('aviso_pago_em' => 'outra-execucao'))
        false
      end

      conferir

      expect(cotacao.reload.proposta).not_to have_key('pago_em')
      expect(cotacao.proposta['aviso_pago_em']).to eq('outra-execucao')
    end

    it 'a fila que recusa (perform_later devolve false) também desfaz' do
      universal('Pago')
      allow(Autonomia::Agents::Operate::EventoDaViagemJob).to receive(:perform_later).and_return(false)

      conferir

      expect(cotacao.reload.proposta.keys).not_to include('pago_em', 'aviso_pago_em')
    end
  end

  it 'cancelado: grava a situação, sem evento' do
    universal('Cancelado')

    conferir

    expect(cotacao.reload.proposta['situacao']).to eq('cancelado')
    expect(eventos).to be_empty
  end

  describe 'aguardando: o lembrete' do
    before { universal('Aguardando Pagamento') }

    it 'sai uma vez entre 12 h e 23 h, de dia, na proposta mais nova' do
      2.times { conferir }

      expect(eventos).to eq([[cotacao.id, evento::LEMBRETE, gerada_em.to_i]])
      expect(cotacao.reload.proposta['lembrete_em']).to eq(agora.iso8601)
    end

    it 'antes de 12 h não sai' do
      cotacao.update!(proposta: proposta.merge('gerada_em' => (agora - 11.hours).iso8601))

      conferir(gerada: (agora - 11.hours).to_i)

      expect(eventos).to be_empty
    end

    it 'depois de 23 h nunca sai (o link vence em 24 h)' do
      cotacao.update!(proposta: proposta.merge('gerada_em' => (agora - 23.hours - 1.minute).iso8601))

      conferir(gerada: (agora - 23.hours - 1.minute).to_i)

      expect(eventos).to be_empty
      expect(cotacao.reload.proposta).not_to have_key('lembrete_em')
    end

    it 'de noite, na hora da conta, não sai' do
      travel_to Time.utc(2026, 11, 27, 1, 0, 0) # 22:00 em São Paulo
      cotacao.update!(proposta: proposta.merge('gerada_em' => 13.hours.ago.iso8601))

      conferir(gerada: 13.hours.ago.to_i)

      expect(eventos).to be_empty
    end

    it 'na proposta mais velha da conversa não sai' do
      cotacao_com(proposta.merge('codigo_carrinho' => 111_222))

      conferir

      expect(eventos).to be_empty
    end

    # #3266: o cliente cotou de novo a mesma viagem. A compra nova cancela o carrinho desta, e o lembrete mandaria um link
    # morto, ainda que a cotação nova não tenha proposta (a compra dela não saiu, ou ainda não foi gerada).
    it 'com uma cotação mais nova da mesma viagem, mesmo sem proposta, não sai' do
      cotacao_com(nil)

      conferir

      expect(eventos).to be_empty
      expect(cotacao.reload.proposta).not_to have_key('lembrete_em')
    end

    it 'com uma cotação mais nova de outra viagem, sai como sempre' do
      Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: bia, id_cotacao: 'c-2',
                                                 planos: [], pedido: { 'idades' => [30] }, proposta: nil)

      conferir

      expect(eventos).to eq([[cotacao.id, evento::LEMBRETE, gerada_em.to_i]])
    end
  end

  describe 'as portas, antes da Universal' do
    before { universal('Pago') }

    it 'porta do contratado fechada: zero chamadas' do
      allow(situacao).to receive(:available_for?).and_return(false)

      conferir

      expect(a_request(:get, "#{base}/v1/StatusPagamento/987654")).not_to have_been_made
    end

    it 'agente desligado: zero chamadas' do
      bia.update!(enabled: false)

      conferir

      expect(a_request(:get, "#{base}/v1/StatusPagamento/987654")).not_to have_been_made
    end

    it 'conta desligada: zero chamadas' do
      account.update!(internal_attributes: { 'autonomia_agents_enabled' => false })

      conferir

      expect(a_request(:get, "#{base}/v1/StatusPagamento/987654")).not_to have_been_made
    end

    it 'gerada_em diferente da reserva (proposta trocada): zero chamadas, nada gravado' do
      conferir(gerada: gerada_em.to_i - 60)

      expect(a_request(:get, "#{base}/v1/StatusPagamento/987654")).not_to have_been_made
      expect(cotacao.reload.proposta).to eq(proposta)
    end

    it 'cotação apagada: nada' do
      id = cotacao.id
      cotacao.destroy!

      expect { described_class.new.perform(id, gerada_em.to_i) }.not_to raise_error
      expect(a_request(:get, "#{base}/v1/StatusPagamento/987654")).not_to have_been_made
    end
  end

  it 'erro da Universal: só log com ids e código, sem nota e sem evento' do
    stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 500, body: 'erro')
    allow(Rails.logger).to receive(:info).and_call_original

    conferir

    expect(Rails.logger).to have_received(:info).with("[autonomia][pagamento_automatico] cotacao=#{cotacao.id} erro_da_universal codigo=indisponivel")
    expect(conversa.messages.reload).to be_empty
    expect(eventos).to be_empty
  end
end
