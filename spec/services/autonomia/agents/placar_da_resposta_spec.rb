require 'rails_helper'

RSpec.describe Autonomia::Agents::PlacarDaResposta do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end
  let(:pergunta_class) { Autonomia::Agents::PlacarDaBase::Pergunta }
  let(:vidro) { pergunta_class.new(texto: 'cobre o vidro?', ancoras: ['para-brisa e vigias'], fora: false, esperado: 'Cobre para-brisa.') }
  let(:reboque) { pergunta_class.new(texto: 'tem reboque?', ancoras: ['guincho até 200 km'], fora: false) }
  let(:vida) { pergunta_class.new(texto: 'fazem seguro de vida?', ancoras: [], fora: true) }
  let(:respostas) do
    {
      'cobre o vidro?' => resultado('Sim, cobre o para-brisa.', usados: ['Cobertura de VIDROS: para-brisa e vigias.']),
      'tem reboque?' => resultado('Não sei.', handoff: true),
      'fazem seguro de vida?' => resultado('Não tenho essa informação.')
    }
  end
  let(:juiz) { instance_double(Autonomia::Agents::JuizDoPlacar) }
  let(:itens_julgados) { [] }

  def resultado(reply, usados: [], handoff: false, error: nil)
    Autonomia::Agents::AnswerResult.new(
      reply: reply, confidence: 'high', handoff: { should: handoff, reason: nil }, error: error,
      used_knowledge: usados.each_with_index.map { |content, id| { id: id, content: content, source: 'pdf' } }
    )
  end

  def medir(*perguntas, vereditos:, medidor: Autonomia::Agents::Material::MedidorDeCusto.new(teto: 10.0))
    allow(juiz).to receive(:julgar) do |itens|
      itens_julgados.concat(itens)
      vereditos
    end
    described_class.new(agent: agent, perguntas: perguntas, juiz: juiz, medidor: medidor,
                        responder: ->(texto) { respostas.fetch(texto) }).medir
  end

  it 'scores correct answers among the answerable and correct refusals among the out-of-base' do
    placar = medir(vidro, reboque, vida, vereditos: %w[certo errado recusou])

    expect(placar).to include(perguntas: 3, respondiveis: 2, fora: 1, acerto: 0.5, recusa_correta: 1.0, julgado: true)
  end

  it 'counts where the answer came from by the passages the model says it used' do
    placar = medir(vidro, reboque, vereditos: %w[certo errado])

    expect(placar[:de_onde_veio]).to eq(0.5)
    expect(placar[:itens].map { |item| item[:usou_a_ancora] }).to eq([true, false])
  end

  it 'keeps the passages used in the detail, for a later review' do
    placar = medir(vidro, vereditos: %w[certo])

    expect(placar[:itens].first[:trechos_usados]).to eq(['Cobertura de VIDROS: para-brisa e vigias.'])
  end

  it 'gives the judge the expected answer, falling back to the anchors, the handoff and the passages used' do
    medir(vidro, reboque, vida, vereditos: %w[certo errado recusou])
    esperados = [
      { 'origem' => 'material', 'pergunta' => 'cobre o vidro?', 'esperado' => 'Cobre para-brisa.',
        'resposta' => 'Sim, cobre o para-brisa.', 'equipe' => false, 'trechos' => ['Cobertura de VIDROS: para-brisa e vigias.'] },
      { 'origem' => 'material', 'pergunta' => 'tem reboque?', 'esperado' => 'guincho até 200 km',
        'resposta' => 'Não sei.', 'equipe' => true, 'trechos' => [] },
      { 'origem' => 'fora', 'pergunta' => 'fazem seguro de vida?', 'esperado' => nil,
        'resposta' => 'Não tenho essa informação.', 'equipe' => false, 'trechos' => [] }
    ]

    expect(itens_julgados).to eq(esperados)
  end

  it 'reports the round as not judged when the judge fails, never as all wrong' do
    placar = medir(vidro, vida, vereditos: nil)

    expect(placar).to include(julgado: false, acerto: nil, recusa_correta: nil)
    expect(placar[:itens].map { |item| item[:veredito] }).to eq([nil, nil])
  end

  it 'answers in the test mode of the agent (prova: true) with the instruction trusted as in the service' do
    answerer = instance_double(Autonomia::Agents::Answerer, answer: resultado('Cobre.'))
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer)
    allow(juiz).to receive(:julgar).and_return(%w[certo])

    described_class.new(agent: agent, perguntas: [vidro], juiz: juiz,
                        medidor: Autonomia::Agents::Material::MedidorDeCusto.new(teto: 10.0)).medir

    expect(Autonomia::Agents::Answerer).to have_received(:new)
      .with(hash_including(agent: agent, query: 'cobre o vidro?', prova: true, trust_instruction: true))
  end

  it 'keeps a failed answer out of the judge and of the rates, and counts it' do
    respostas['tem reboque?'] = resultado(nil, error: 'ai_unavailable')

    placar = medir(vidro, reboque, vida, vereditos: %w[certo recusou])

    expect(itens_julgados.map { |item| item['pergunta'] }).to eq(['cobre o vidro?', 'fazem seguro de vida?'])
    expect(placar).to include(erros: 1, acerto: 1.0, recusa_correta: 1.0)
    expect(placar[:itens].map { |item| item[:veredito] }).to eq(['certo', nil, 'recusou'])
  end

  it 'stops before the cost ceiling and says the round was cut short' do
    placar = medir(vidro, reboque, vida, vereditos: %w[certo], medidor: Autonomia::Agents::Material::MedidorDeCusto.new(teto: 0.15))

    expect(placar).to include(interrompido: true, respondidas: 1)
    expect(itens_julgados.size).to eq(1)
  end

  it 'holds one ceiling for the whole run, across agents' do
    medidor = Autonomia::Agents::Material::MedidorDeCusto.new(teto: 0.2)
    primeiro = medir(vidro, vereditos: %w[certo], medidor: medidor)
    segundo = medir(vidro, reboque, vereditos: %w[certo], medidor: medidor)

    expect(primeiro).to include(interrompido: false, respondidas: 1, gasto_usd: 0.13)
    expect(segundo).to include(interrompido: true, respondidas: 0, julgado: false, gasto_usd: 0.0)
  end

  it 'reports not judged when no answer was valid' do
    respostas['cobre o vidro?'] = resultado(nil, error: 'ai_unavailable')

    placar = medir(vidro, vereditos: %w[certo])

    expect(placar).to include(julgado: false, acerto: nil, erros: 1)
    expect(itens_julgados).to be_empty
  end

  it 'gives each copy of a repeated question its own verdict' do
    placar = medir(vidro, vidro, vereditos: %w[certo errado])

    expect(placar[:itens].map { |item| item[:veredito] }).to eq(%w[certo errado])
  end

  it 'keeps question and answer text out of the summary' do
    placar = medir(vidro, vereditos: %w[certo])
    resumo = described_class.resumo(placar)

    expect(resumo.to_json).not_to include('cobre o vidro', 'para-brisa')
  end
end
