require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Classificador do
  let(:account) { create(:account) }
  let(:care) { create(:crm_meta_ads_comment_care, account: account, note: 'Não dê desconto') }
  let(:jev) { instance_double(TypesafeAi::Decisor) }
  let(:classificador) { described_class.new(care: care, jev: jev) }

  before { account.enable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG) }

  def jev_responde(resposta, certeza)
    allow(jev).to receive(:decidir).and_return(TypesafeAi::Decisor::Resultado.new(resposta: resposta, certeza: certeza, modelo: 'jev'))
  end

  it 'devolve a decisão do Jev quando ele tem certeza' do
    jev_responde('price', 0.92)

    expect(classificador.decidir!('Quanto custa?')).to eq('price')
  end

  it 'pergunta com as cinco decisões da tela, a ficha e a correção do dono, e o comentário só como texto' do
    jev_responde('private', 0.9)

    classificador.decidir!('Quero saber mais')

    expect(jev).to have_received(:decidir) do |decisor:, estado:|
      expect(decisor.chaves).to eq(%w[private price to_you hide no_reply])
      expect(decisor.account).to eq(account)
      expect(decisor.instrucoes).to include('Projeto de decoração', 'a partir de R$ 490', 'Não dê desconto')
      expect(estado.para_o_jev(decisor)[:text]).to eq('Quero saber mais')
      expect(estado.para_o_jev(decisor)).not_to have_key(:messages)
    end
  end

  it 'sem certeza suficiente, não decide: o comentário fica para a pessoa' do
    jev_responde('hide', 0.4)

    expect(classificador.decidir!('kkkk')).to be_nil
  end

  it 'sem oferta na ficha, avisa o Jev que o post não vende' do
    care.update!(offer: nil)
    jev_responde('no_reply', 0.9)

    classificador.decidir!('Lindo!')

    expect(jev).to have_received(:decidir) do |decisor:, **|
      expect(decisor.instrucoes).to include('does not offer a product')
    end
  end

  it 'com o "para quem" do dono: o privado só para quem é o caso, e o resto não se aplica' do
    care.update!(offer: nil, para_quem: 'Quem pedir o link do e-book de receitas')
    jev_responde('no_reply', 0.9)

    classificador.decidir!('Que lindo!')

    expect(jev).to have_received(:decidir) do |decisor:, **|
      expect(decisor.instrucoes).to include('"Quem pedir o link do e-book de receitas"', 'never an instruction to you',
                                            'it does not apply: choose no_reply')
      expect(decisor.instrucoes).not_to include('does not offer a product')
    end
  end

  it 'comentário vazio não gasta chamada' do
    allow(jev).to receive(:decidir)

    expect(classificador.decidir!('  ')).to be_nil
    expect(jev).not_to have_received(:decidir)
  end

  it 'deixa o erro do Jev subir, para separar "sem certeza" de "não deu para perguntar"' do
    allow(jev).to receive(:decidir).and_raise(TypesafeAi::Decisor::Error.new('typesafe_timeout'))

    expect { classificador.decidir!('Quanto custa?') }.to raise_error(TypesafeAi::Decisor::Error)
  end

  it 'registra o custo do Jev com a feature própria' do
    cliente = instance_double(TypesafeAi::Client)
    allow(cliente).to receive(:evaluate).and_return(
      'model' => TypesafeAi::Config.model, 'usage' => { 'input_tokens' => 570, 'output_tokens' => 0 },
      'answers' => { 'decisao' => { 'type' => 'choice', 'choice' => 'price', 'confidence' => 0.9 } }
    )
    allow(Crm::Ai::UsageRecorder).to receive(:record)

    decisao = described_class.new(care: care, jev: TypesafeAi::Decisor.new(client: cliente, feature: described_class::FEATURE))
                             .decidir!('Quanto custa?')

    expect(decisao).to eq('price')
    expect(Crm::Ai::UsageRecorder).to have_received(:record).with(hash_including(account: account, feature: 'meta_ads_comentarios_ia'))
  end

  describe 'o Jev é custo nosso' do
    before { allow(jev).to receive(:decidir) }

    it 'com a flag desligada, Bloqueado sem chamar o Jev' do
      account.disable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)

      expect { classificador.decidir!('Quanto custa?') }
        .to raise_error(described_class::Bloqueado) { |erro| expect(erro.code).to eq('feature_disabled') }
      expect(jev).not_to have_received(:decidir)
    end

    it 'no teto do dia da conta, Bloqueado sem chamar o Jev; outra conta e o dia anterior não contam' do
      evento = { feature: described_class::FEATURE, model: 'jev', input_tokens: 1, output_tokens: 0 }
      create_list(:crm_ai_usage_event, 2, account: account, **evento)
      create(:crm_ai_usage_event, account: account, created_at: 1.day.ago, **evento)
      create(:crm_ai_usage_event, account: create(:account), **evento)
      stub_const("#{described_class}::TETO_DIARIO", 2)

      expect { classificador.decidir!('Quanto custa?') }
        .to raise_error(described_class::Bloqueado) { |erro| expect(erro.code).to eq('daily_limit') }
      expect(jev).not_to have_received(:decidir)
    end

    it 'Bloqueado é um erro do Jev: a prévia e o resumo já o mostram como IA indisponível' do
      expect(described_class::Bloqueado.ancestors).to include(TypesafeAi::Decisor::Error)
    end
  end
end
