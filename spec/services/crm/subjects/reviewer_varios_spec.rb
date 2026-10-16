require 'rails_helper'

# #1693: com vários assuntos por mensagem, o modelo maior devolve uma lista, conferida item a item.
RSpec.describe Crm::Subjects::Reviewer do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').first }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:jev) { TypesafeAi::Decisor::Resultado.new(resposta: Crm::Subjects::Question::VARIOS, certeza: 0.9) }
  let(:estado) { instance_double(Autonomia::Decisores::Estado, conversa: { mensagens: [] }) }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def question(varios:)
    Crm::Subjects::Question.new(account: account, pipelines: [pipeline], cards: [], atual: nil, varios: varios)
  end

  def revisar(resposta, varios: true)
    allow(cliente).to receive(:create).and_return(text: resposta.to_json)
    described_class.new(question(varios: varios)).revisar(estado, jev)
  end

  it 'devolve a lista e o principal, com o schema e as instruções de vários assuntos' do
    veredito = revisar({ assuntos: [{ resposta: "novo_#{pipeline.id}", titulo: 'Seguro auto' },
                                    { resposta: "novo_#{pipeline.id}", titulo: 'Seguro residencial' }],
                         principal: 1, seguro: true, motivo: 'ok' })

    expect(veredito).to have_attributes(resposta: "novo_#{pipeline.id}", titulo: 'Seguro residencial', seguro: true, principal: 1)
    expect(veredito.assuntos.map(&:titulo)).to eq(['Seguro auto', 'Seguro residencial'])
    expect(cliente).to have_received(:create).with(hash_including(instructions: described_class::INSTRUCOES_VARIOS,
                                                                  schema: hash_including(name: 'assuntos_revisao')))
  end

  it 'lista vazia é nenhum assunto' do
    expect(revisar({ assuntos: [], principal: 0, seguro: true, motivo: 'só agradeceu' }).resposta)
      .to eq(Crm::Subjects::Question::SEM_ASSUNTO)
  end

  it 'recusa a resposta inteira com uma chave fora das opções ou o principal fora da lista' do
    expect { revisar({ assuntos: [{ resposta: 'card_999', titulo: '' }], principal: 0, seguro: true, motivo: 'x' }) }
      .to raise_error(described_class::Error, 'resposta_invalida')
    expect { revisar({ assuntos: [{ resposta: "novo_#{pipeline.id}", titulo: 'A' }], principal: 3, seguro: true, motivo: 'x' }) }
      .to raise_error(described_class::Error, 'resposta_invalida')
  end

  it 'sem a flag, a pergunta é a de um assunto, como antes' do
    veredito = revisar({ resposta: "novo_#{pipeline.id}", titulo: 'Seguro auto', seguro: true, motivo: 'ok' }, varios: false)

    expect(veredito).to have_attributes(resposta: "novo_#{pipeline.id}", titulo: 'Seguro auto', assuntos: nil)
    expect(cliente).to have_received(:create).with(hash_including(instructions: described_class::INSTRUCOES,
                                                                  schema: hash_including(name: 'assunto_revisao')))
  end
end
