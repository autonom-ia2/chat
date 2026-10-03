require 'rails_helper'

RSpec.describe Autonomia::Decisores::Aplicador do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'joana@cliente.com', email: 'joana@cliente.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:campos) do
    [{ chave: 'nome', descricao: 'Nome', destino: 'contato.nome' },
     { chave: 'telefone', descricao: 'Telefone', destino: 'contato.telefone' },
     { chave: 'empresa', descricao: 'Empresa', destino: 'empresa.nome' },
     { chave: 'produto', descricao: 'Produto', destino: 'contato.atributo:produto' },
     { chave: 'titulo', descricao: 'Título', destino: 'card.titulo' }]
  end
  let(:decisor) { create(:autonomia_decisor, account: account, campos: campos) }

  before { create(:custom_attribute_definition, account: account, attribute_key: 'produto', attribute_model: 'contact_attribute') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def aplicar(valores)
    described_class.new(decisor: decisor, conversation: conversation).aplicar(valores)
  end

  it 'grava nome, telefone, empresa e atributo no contato da conversa' do
    resultado = aplicar('nome' => 'Joana Lima', 'telefone' => '+5511988887777', 'empresa' => 'Lima Seguros', 'produto' => 'Auto')

    expect(contact.reload).to have_attributes(name: 'Joana Lima', phone_number: '+5511988887777')
    expect(contact.custom_attributes).to include('produto' => 'Auto')
    expect(contact.company.name).to eq('Lima Seguros')
    expect(resultado.aplicados.keys).to contain_exactly('nome', 'telefone', 'empresa', 'produto')
  end

  it 'reaproveita a empresa de mesmo nome na conta' do
    empresa = Company.create!(account_id: account.id, name: 'Lima Seguros')

    expect { aplicar('empresa' => 'lima seguros') }.not_to change(Company, :count)
    expect(contact.reload.company_id).to eq(empresa.id)
  end

  it 'deixa de fora o telefone que o contato recusa, sem impedir os outros campos' do
    # O telefone vem antes do nome: o valor recusado não pode contaminar a gravação seguinte.
    decisor.update!(campos: campos.values_at(1, 0))
    resultado = aplicar('telefone' => '11 98888-7777', 'nome' => 'Joana Lima')

    expect(contact.reload).to have_attributes(name: 'Joana Lima', phone_number: nil)
    expect(resultado.aplicados).to eq('nome' => 'Joana Lima')
  end

  it 'devolve o campo de card quando a conversa ainda não tem card, e grava quando tem' do
    expect(aplicar('titulo' => 'Seguro auto').sem_card).to eq('titulo' => 'Seguro auto')

    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, primary_conversation: conversation, title: 'Lead')

    expect(aplicar('titulo' => 'Seguro auto').aplicados).to eq('titulo' => 'Seguro auto')
    expect(card.reload.title).to eq('Seguro auto')
  end
end
