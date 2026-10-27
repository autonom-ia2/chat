require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Classificador do
  let(:account) { create(:account) }
  let(:care) { create(:crm_meta_ads_comment_care, account: account, note: 'Não dê desconto') }
  let(:jev) { instance_double(TypesafeAi::Decisor) }
  let(:classificador) { described_class.new(care: care, jev: jev) }

  def jev_responde(resposta, certeza)
    allow(jev).to receive(:decidir).and_return(TypesafeAi::Decisor::Resultado.new(resposta: resposta, certeza: certeza, modelo: 'jev'))
  end

  it 'devolve a decisão do Jev quando ele tem certeza' do
    jev_responde('price', 0.92)

    expect(classificador.decidir('Quanto custa?')).to eq('price')
  end

  it 'pergunta com as cinco decisões da tela, a ficha e a correção do dono, e o comentário só como texto' do
    jev_responde('private', 0.9)

    classificador.decidir('Quero saber mais')

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

    expect(classificador.decidir('kkkk')).to be_nil
  end

  it 'sem oferta na ficha, avisa o Jev que o post não vende' do
    care.update!(offer: nil)
    jev_responde('no_reply', 0.9)

    classificador.decidir('Lindo!')

    expect(jev).to have_received(:decidir) do |decisor:, **|
      expect(decisor.instrucoes).to include('does not offer a product')
    end
  end

  it 'comentário vazio não gasta chamada' do
    allow(jev).to receive(:decidir)

    expect(classificador.decidir('  ')).to be_nil
    expect(jev).not_to have_received(:decidir)
  end

  it 'erro do Jev vira nil, sem derrubar o job' do
    allow(jev).to receive(:decidir).and_raise(TypesafeAi::Decisor::Error.new('typesafe_timeout'))

    expect(classificador.decidir('Quanto custa?')).to be_nil
  end

  it 'registra o custo com a feature própria' do
    expect(described_class::FEATURE).to eq('meta_ads_comentarios_ia')
  end
end
