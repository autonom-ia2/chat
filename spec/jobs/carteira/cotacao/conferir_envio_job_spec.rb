require 'rails_helper'

# E8 (#2901): MINUTOS_PARA_INCERTA depois da reserva do envio da proposta. Com o id da mensagem, nada a fazer; sem ele,
# o passo vira incerto e a equipe é avisada, uma vez só. Tudo fictício.
RSpec.describe Carteira::Cotacao::ConferirEnvioJob do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:caixa) { caixa_oficial(account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { por_em_renovacao(seguro, cotacao_ligada(account, user: admin, caixa: caixa)) }

  def avisos
    Crm::FollowUp.where(account_id: account.id).map { |tarefa| tarefa.metadata['motivo'] }
  end

  it 'o passo com o id da mensagem: nada muda e ninguém é avisado' do
    passo = Carteira::Cotacao.registrar(seguro, 'proposta_enviada', { mensagem_id: 42 }, user: admin)

    described_class.perform_now(passo.id)

    expect(passo.reload.valores).not_to have_key('incerta')
    expect(avisos).to be_empty
  end

  it 'o passo sem o id: vira incerto e avisa a equipe uma vez, mesmo rodando de novo' do
    passo = Carteira::Cotacao.registrar(seguro, 'proposta_enviada', user: admin)
    expect(Carteira::Cotacao::Aviso).to receive(:new).once.and_call_original

    2.times { described_class.perform_now(passo.id) }

    expect(passo.reload.valores).to include('incerta' => true)
    expect(avisos).to eq(['proposta_incerta'])
  end

  it 'o passo que sumiu: nada a fazer' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
