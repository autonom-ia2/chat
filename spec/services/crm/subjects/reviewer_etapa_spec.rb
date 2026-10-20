require 'rails_helper'

# #1910: com a coluna do card novo, a etapa que o modelo maior devolve é conferida como a resposta.
RSpec.describe Crm::Subjects::Reviewer do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:pipeline) { pipeline_e_etapa.first }
  let!(:sinistros) do
    create_crm_stage(account: account, pipeline: pipeline, name: 'Sinistros', position: 1)
      .tap { |stage| stage.update!(metadata: { 'ai_criteria' => 'Cliente fala de sinistro' }) }
  end
  let!(:sem_frase) { create_crm_stage(account: account, pipeline: pipeline, name: 'Outros', position: 2) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:jev) { TypesafeAi::Decisor::Resultado.new(resposta: "novo_#{pipeline.id}", certeza: 0.9) }
  let(:estado) { instance_double(Autonomia::Decisores::Estado, conversa: { mensagens: [] }) }

  before do
    pipeline.update!(counts_as_sale: false)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def revisar(resposta, varios: false, etapas: true)
    allow(cliente).to receive(:create).and_return(text: resposta.to_json)
    question = Crm::Subjects::Question.new(account: account, pipelines: [pipeline], cards: [], atual: nil, varios: varios, etapas: etapas)
    described_class.new(question).revisar(estado, jev)
  end

  it 'devolve a etapa escolhida, e só etapas com frase são opção' do
    veredito = revisar({ resposta: "novo_#{pipeline.id}", titulo: 'Sinistro', seguro: true, motivo: 'ok', etapa: "etapa_#{sinistros.id}" })

    expect(veredito.etapa).to eq("etapa_#{sinistros.id}")
    expect(cliente).to have_received(:create).with(hash_including(schema: hash_including(schema: hash_including(
      properties: hash_including(etapa: { type: 'string', enum: [Crm::Subjects::Etapa::NENHUMA, "etapa_#{sinistros.id}"] })
    ))))
  end

  it 'recusa a resposta inteira com uma etapa fora das opções' do
    expect { revisar({ resposta: "novo_#{pipeline.id}", titulo: 'X', seguro: true, motivo: 'ok', etapa: "etapa_#{sem_frase.id}" }) }
      .to raise_error(described_class::Error, 'resposta_invalida')
    expect { revisar({ resposta: "novo_#{pipeline.id}", titulo: 'X', seguro: true, motivo: 'ok' }) }
      .to raise_error(described_class::Error, 'resposta_invalida')
  end

  it 'na lista de vários assuntos, cada item traz a etapa dele e o principal leva a sua' do
    veredito = revisar({ assuntos: [{ resposta: "novo_#{pipeline.id}", titulo: 'A', seguro: true, etapa: Crm::Subjects::Etapa::NENHUMA },
                                    { resposta: "novo_#{pipeline.id}", titulo: 'B', seguro: true, etapa: "etapa_#{sinistros.id}" }],
                         principal: 1, motivo: 'ok' }, varios: true)

    expect(veredito.assuntos.map(&:etapa)).to eq([Crm::Subjects::Etapa::NENHUMA, "etapa_#{sinistros.id}"])
    expect(veredito.etapa).to eq("etapa_#{sinistros.id}")
  end

  it 'num assunto que não é pedido novo, a etapa não conta e não derruba a resposta' do
    veredito = revisar({ resposta: Crm::Subjects::Question::SEM_ASSUNTO, titulo: '', seguro: true, motivo: 'só cumprimentou',
                         etapa: 'qualquer' })

    expect(veredito).to have_attributes(resposta: Crm::Subjects::Question::SEM_ASSUNTO, etapa: nil)
  end

  it 'sem etapa candidata em nenhum funil, a pergunta é a de sempre' do
    sinistros.update!(metadata: {})

    veredito = revisar({ resposta: "novo_#{pipeline.id}", titulo: 'Sinistro', seguro: true, motivo: 'ok' })

    expect(veredito.etapa).to be_nil
    expect(cliente).to have_received(:create).with(hash_including(instructions: described_class::INSTRUCOES))
  end
end
