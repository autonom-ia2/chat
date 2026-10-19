require 'rails_helper'

# #1426 (tema 4b) — contradição entre materiais aprovados: o MODELO aponta (a lista vazia é resposta válida), o código só
# confere ids e tamanhos. Decidida pela pessoa, fica enquanto os dois materiais existirem; as não decididas são trocadas.
RSpec.describe Autonomia::Agents::Material::Contradicoes do
  include_context 'with material do agente'

  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let!(:site) { material('www.lanchesdabia.com.br', trechos: ['Sábado das 9h às 13h.']) }
  let!(:horarios) { material('horarios.pdf', trechos: ['Sábado das 9h às 12h.']) }

  before do
    credencial_de_teste
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def modelo_aponta(*itens)
    allow(cliente).to receive(:create).and_return(resposta_do_modelo(contradicoes: itens))
  end

  def horario_de_sabado(lado_a = site.id, lado_b = horarios.id)
    { assunto: 'horário de sábado', fonte_a: lado_a, diz_a: 'das 9h às 13h', fonte_b: lado_b, diz_b: 'das 9h às 12h' }
  end

  def gravadas
    agent.reload.config.dig('conferencia_da_base', 'contradicoes')
  end

  it 'grava a contradição com os dois materiais e sem escolha', :aggregate_failures do
    modelo_aponta(horario_de_sabado)

    described_class.new(agent).conferir!

    item = gravadas.sole
    expect(item['assunto']).to eq('horário de sábado')
    expect(item['opcoes']).to eq([{ 'fonte' => site.id, 'diz' => 'das 9h às 13h' }, { 'fonte' => horarios.id, 'diz' => 'das 9h às 12h' }])
    expect(item['escolha']).to be_nil
    expect(item['id']).to start_with('contradicao-')
    expect(agent.config.dig('conferencia_da_base', 'hash_da_base')).to eq(Autonomia::Agents::Material.hash_da_base(agent))
  end

  it 'lista vazia do modelo: nenhuma contradição' do
    modelo_aponta

    described_class.new(agent).conferir!

    expect(gravadas).to eq([])
  end

  it 'descarta material que não é deste agente, o mesmo dos dois lados e "diz" vazio' do
    outro = Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'support')
    alheio = material('alheio.pdf', dono: outro)
    modelo_aponta(horario_de_sabado(site.id, alheio.id), horario_de_sabado(site.id, site.id),
                  horario_de_sabado.merge(diz_b: '  '))

    described_class.new(agent).conferir!

    expect(gravadas).to eq([])
  end

  it 'a decidida fica (e vai ao modelo como já decidida); a não decidida é trocada' do
    decidida = { 'id' => 'contradicao-x', 'assunto' => 'preço do X-Burger', 'escolha' => site.id,
                 'opcoes' => [{ 'fonte' => site.id, 'diz' => 'R$ 25' }, { 'fonte' => horarios.id, 'diz' => 'R$ 27' }] }
    velha = decidida.merge('id' => 'contradicao-y', 'escolha' => nil, 'assunto' => 'taxa de entrega')
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', { 'contradicoes' => [decidida, velha] })
    modelo_aponta(horario_de_sabado)

    described_class.new(agent).conferir!

    expect(gravadas.pluck('assunto')).to eq(['preço do X-Burger', 'horário de sábado'])
    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:input].first[:content].first[:text]).to include('JA DECIDIDAS PELO DONO', 'preço do X-Burger')
    end
  end

  it 'decidida cujo material saiu deixa de valer' do
    decidida = { 'id' => 'contradicao-x', 'assunto' => 'preço', 'escolha' => site.id,
                 'opcoes' => [{ 'fonte' => site.id, 'diz' => 'R$ 25' }, { 'fonte' => horarios.id, 'diz' => 'R$ 27' }] }
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', { 'contradicoes' => [decidida] })
    horarios.destroy!
    modelo_aponta

    described_class.new(agent).conferir!

    expect(gravadas).to eq([])
    expect(cliente).not_to have_received(:create)
  end

  it 'IA indisponível: nada muda' do
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', { 'contradicoes' => [{ 'id' => 'a' }] })
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'fora')

    expect(described_class.new(agent).conferir!).to be_nil
    expect(gravadas).to eq([{ 'id' => 'a' }])
  end

  it 'material reprovado não entra na conferência' do
    reprovado = material('borrado.jpg', review_status: 'needs_resend')
    modelo_aponta

    described_class.new(agent).conferir!

    expect(cliente).to have_received(:create) do |**kwargs|
      texto = kwargs[:input].first[:content].first[:text]
      expect(texto).not_to include("\"id\": #{reprovado.id},")
      expect(texto).to include('Sábado das 9h às 13h.', 'Sábado das 9h às 12h.')
    end
  end
end
