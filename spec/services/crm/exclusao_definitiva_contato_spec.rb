require 'rails_helper'

# #2096: excluir o contato pela rota nova trava o contato antes de tudo. Dois cliques não gravam duas linhas na
# Auditoria, e os cards são relidos sob a trava.
RSpec.describe Crm::ExclusaoDefinitiva do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990061') }
  let!(:card) do
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', status: :open)
  end

  before { account.enable_features!(:crm_arquivados) }

  def auditorias
    Audited.audit_class.where(auditable: account, action: described_class::ACAO)
  end

  it 'keep duas vezes (dois cliques): o segundo encontra o contato já excluído e não audita de novo' do
    segunda_aba = Contact.find(contact.id)

    described_class.contato!(contact: contact, user: admin, modo: 'keep')

    expect { described_class.contato!(contact: segunda_aba, user: admin, modo: 'keep') }
      .to raise_error(described_class::Mudou) { |erro| expect(erro.motivo).to eq('already_deleted') }
    expect(auditorias.count).to eq(1)
  end

  it 'delete duas vezes: o segundo desiste sem apagar nem auditar' do
    segunda_aba = Contact.find(contact.id)

    described_class.contato!(contact: contact, user: admin, modo: 'delete')

    expect { described_class.contato!(contact: segunda_aba, user: admin, modo: 'delete') }
      .to raise_error(described_class::Mudou) { |erro| expect(erro.motivo).to eq('already_deleted') }
    expect(auditorias.count).to eq(1)
  end

  it 'delete: card que entrou depois da leitura faz desistir sob a trava, em vez de apagar uma lista velha' do
    pipeline, stage = pipeline_and_stage
    novo = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Novo', status: :open)

    expect { described_class.conferir_cards_do_contato!(contact, [card.id]) }
      .to raise_error(described_class::Mudou) { |erro| expect(erro.motivo).to eq('cards_changed') }
    expect { described_class.conferir_cards_do_contato!(contact, [novo.id, card.id]) }.not_to raise_error
  end
end
