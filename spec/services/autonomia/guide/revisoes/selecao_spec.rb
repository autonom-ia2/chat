require 'rails_helper'

# Quais conversas a revisão lê (#3158, B8b): o filtro do modelo, com a permissão de quem pergunta.
RSpec.describe Autonomia::Guide::Revisoes::Selecao do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent) }
  let(:caixa_dele) { create(:inbox, account: account) }
  let(:outra_caixa) { create(:inbox, account: account) }
  let(:semana) { { 'de' => '2026-11-17', 'ate' => '2026-11-23' } }

  before { create(:inbox_member, user: atendente, inbox: caixa_dele) }

  def conversa(quando, caixa: caixa_dele, **atributos)
    create(:conversation, account: account, inbox: caixa, created_at: Time.zone.parse(quando), **atributos)
  end

  def nota(conversa, valor, quando)
    create(:csat_survey_response, account: account, conversation: conversa, contact: conversa.contact, rating: valor,
                                  message: create(:message, conversation: conversa, account: account, inbox: conversa.inbox),
                                  created_at: Time.zone.parse(quando))
  end

  def ids(params, quem: admin)
    described_class.new(account: account, user: quem, params: params).ids
  end

  it 'pega as conversas do período, da mais nova para a mais antiga' do
    antiga = conversa('2026-11-18 10:00')
    nova = conversa('2026-11-22 10:00')
    conversa('2026-11-10 10:00')

    expect(ids(semana)).to eq([nova.id, antiga.id])
  end

  it 'com notas, vale a data da nota e só as notas pedidas' do
    baixa = conversa('2026-11-01 10:00')
    nota(baixa, 1, '2026-11-20 10:00')
    nota(conversa('2026-11-01 10:00'), 5, '2026-11-20 10:00')
    nota(conversa('2026-11-01 10:00'), 2, '2026-11-02 10:00')

    expect(ids(semana.merge('notas' => [1, 2]))).to eq([baixa.id])
  end

  it 'quem não é administrador só revisa o que vê na caixa' do
    dele = conversa('2026-11-20 10:00')
    conversa('2026-11-20 10:00', caixa: outra_caixa)

    expect(ids(semana, quem: atendente)).to eq([dele.id])
  end

  it 'filtra por caixa e status' do
    aberta = conversa('2026-11-20 10:00', status: :open)
    conversa('2026-11-20 10:00', status: :resolved)
    conversa('2026-11-20 10:00', caixa: outra_caixa, status: :open)

    expect(ids(semana.merge('caixa_id' => caixa_dele.id.to_s, 'status' => 'open'))).to eq([aberta.id])
  end

  it 'recusa data fora do formato e período invertido', :aggregate_failures do
    expect { ids({ 'de' => 'ontem', 'ate' => '2026-11-23' }) }.to raise_error(described_class::Recusado, /AAAA-MM-DD/)
    expect { ids({ 'de' => '2026-11-23', 'ate' => '2026-11-17' }) }.to raise_error(described_class::Recusado)
  end

  it 'pede filtro a mais acima do teto' do
    stub_const('Autonomia::Guide::Revisao::MAX_IDS', 1)
    2.times { conversa('2026-11-20 10:00') }

    expect { ids(semana) }.to raise_error(described_class::Recusado, /período menor/)
  end
end
