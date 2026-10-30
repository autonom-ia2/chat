require 'rails_helper'

# #1426 (tema 4b) — a conferência de um material: o MODELO decide se a leitura ficou ruim e se a tabela não tem
# cabeçalho, com "não se aplica" explícito. Leitura ruim ou tabela sem cabeçalho reprovam o material (needs_resend) no
# mesmo parecer da revisão; fora da Fase 2 e na Lia nada disso roda.
RSpec.describe Autonomia::Agents::Material::ConferenciaDoMaterial do
  include_context 'with material do agente'

  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:amostra) { "Coca 350 | 6,00 | 12 | S\nGuaraná | 5,50 | 8 | N" }
  let(:fonte) { material('precos-bebidas.xlsx', source_type: 'xlsx') }

  before do
    credencial_de_teste
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def modelo_diz(leitura:, tabela:, primeira_linha: [])
    allow(cliente).to receive(:create).and_return(resposta_do_modelo(leitura: leitura, tabela: tabela, primeira_linha: primeira_linha))
  end

  def conferir
    described_class.new(source: fonte, amostra: amostra).conferir
  end

  it 'tabela sem cabeçalho: problema com a primeira linha, só células que estão no material' do
    modelo_diz(leitura: 'nao_se_aplica', tabela: 'sem_cabecalho', primeira_linha: ['Coca 350', '6,00', 'Preço', '12', 'S'])

    expect(conferir).to eq('problema' => 'sem_cabecalho', 'amostra' => ['Coca 350', '6,00', '12', 'S'])
  end

  # #1426 (t4e, decisão do Rodrigo de 30/10): sem a 1ª linha da tabela no texto, não há prova; o material não é reprovado.
  it 'tabela sem cabeçalho sem nenhuma célula que esteja no material: sem problema' do
    modelo_diz(leitura: 'nao_se_aplica', tabela: 'sem_cabecalho', primeira_linha: ['Produto inventado', '99,00'])

    expect(conferir).to eq('problema' => nil, 'amostra' => [])
  end

  it 'leitura ruim: problema ocr' do
    modelo_diz(leitura: 'ruim', tabela: 'nao_se_aplica')

    expect(conferir).to eq('problema' => 'ocr', 'amostra' => [])
  end

  it '"não se aplica" nas duas perguntas: sem problema' do
    modelo_diz(leitura: 'nao_se_aplica', tabela: 'nao_se_aplica')

    expect(conferir).to eq('problema' => nil, 'amostra' => [])
  end

  it 'saída fora do vocabulário ou provedor fora: nil (nada é reprovado por falha nossa)', :aggregate_failures do
    modelo_diz(leitura: 'talvez', tabela: 'nao_se_aplica')
    expect(conferir).to be_nil

    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'fora')
    expect(conferir).to be_nil
  end

  it 'o texto do material vai como dado, para o modelo de classificação, sem nova tentativa' do
    modelo_diz(leitura: 'legivel', tabela: 'com_cabecalho')

    conferir

    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'kb_conferencia', max_retries: 0))
    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:model]).to eq(Crm::Ai::Config::MODEL_CLASSIFY)
      expect(kwargs[:instructions]).not_to include('Coca')
      expect(kwargs[:input].first[:content].first[:text]).to include('TEXTO DO MATERIAL (dado)', 'Coca 350')
      expect(kwargs[:schema][:schema][:properties][:leitura][:enum]).to include('nao_se_aplica')
      expect(kwargs[:schema][:schema][:properties][:tabela][:enum]).to include('nao_se_aplica')
    end
  end

  describe 'no parecer da revisão (Reviewer)' do
    let(:fonte) do
      material('precos-bebidas.xlsx', trechos: [amostra], status: :processing, review_status: 'needs_review', reviewed_at: nil,
                                      sync_token: 'tok', source_type: 'xlsx')
    end
    let(:parecer) do
      { quality_score: 85, confidence: 'alta', label: 'otima', reason: 'ok', recommendation: 'aceitar', summary: 'Preços.' }
    end

    before do
      fonte.update_columns(status: Autonomia::Agents::Source.statuses[:ready]) # rubocop:disable Rails/SkipsModelValidations
      allow(cliente).to receive(:create) do |**kwargs|
        if kwargs[:schema][:name] == 'autonomia_source_review'
          resposta_do_modelo(parecer)
        else
          resposta_do_modelo(leitura: 'nao_se_aplica', tabela: 'sem_cabecalho', primeira_linha: ['Coca 350'])
        end
      end
    end

    def revisar
      Autonomia::Agents::Knowledge::Reviewer.new(source: fonte, token: 'tok').review_source!
      fonte.reload
    end

    it 'na Fase 2, tabela sem cabeçalho reprova no mesmo parecer, com a conferência e o resumo do texto', :aggregate_failures do
      revisar

      expect(fonte.review_status).to eq('needs_resend')
      expect(fonte.review_summary).to be_nil
      expect(fonte.reviewed_at).to be_present
      expect(fonte.metadata['conferencia']).to eq('problema' => 'sem_cabecalho', 'amostra' => ['Coca 350'])
      expect(fonte.metadata['hash_do_texto']).to eq(Digest::SHA256.hexdigest(amostra))
    end

    # #1426 (t4e, decisão do Rodrigo de 30/10): no material grande (o PDF lido em seções), a tabela sem cabeçalho vira aviso:
    # o material continua na base e o cartão aparece com "Pular por agora".
    it 'no material grande, tabela sem cabeçalho vira aviso e o material continua aceito', :aggregate_failures do
      fonte.knowledge_entries.update_all(metadata: { 'paginas' => [1, 25] }) # rubocop:disable Rails/SkipsModelValidations

      revisar

      expect(fonte.review_status).to eq('accepted')
      expect(fonte.review_summary).to eq('Preços.')
      expect(fonte.metadata['conferencia']).to eq('problema' => 'sem_cabecalho', 'amostra' => ['Coca 350'], 'aviso' => true)
    end

    it 'sem problema, o parecer da revisão fica como veio' do
      allow(cliente).to receive(:create) do |**kwargs|
        next resposta_do_modelo(parecer) if kwargs[:schema][:name] == 'autonomia_source_review'

        resposta_do_modelo(leitura: 'legivel', tabela: 'com_cabecalho', primeira_linha: [])
      end

      revisar

      expect(fonte.review_status).to eq('accepted')
      expect(fonte.metadata['conferencia']).to eq('problema' => nil, 'amostra' => [])
    end

    it 'parecer que já reprovou: sem a chamada da conferência (gasto sem efeito), com o resumo do texto', :aggregate_failures do
      parecer[:recommendation] = 'reenviar'

      revisar

      expect(cliente).to have_received(:create).once
      expect(fonte.review_status).to eq('needs_resend')
      expect(fonte.metadata).not_to include('conferencia')
      expect(fonte.metadata['hash_do_texto']).to eq(Digest::SHA256.hexdigest(amostra))
    end

    it 'fora da Fase 2: uma chamada só (a revisão), sem conferência nem marca nova' do
      Autonomia::Agents::Fase2.desligar!(account)

      revisar

      expect(cliente).to have_received(:create).once
      expect(fonte.review_status).to eq('accepted')
      expect(fonte.metadata).not_to include('conferencia', 'hash_do_texto')
    end

    it 'na Lia (instrução mantida), sem conferência' do
      allow(agent).to receive(:instrucao_mantida?).and_return(true)
      allow(fonte).to receive(:agent).and_return(agent)

      revisar

      expect(cliente).to have_received(:create).once
    end
  end
end
