require 'rails_helper'

# O número de uma leitura (`Medida`) e a pergunta fechada ao Jev (`Triagem`), do pulso do Guia (#935).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Guia: medida e triagem do aviso' do
  describe Autonomia::Guide::Medida do
    let(:corpo) do
      { 'payload' => [{ 'id' => 1, 'ok' => true, 'disparos' => { 'hora' => 3 } }, { 'id' => 2, 'ok' => false, 'disparos' => { 'hora' => 9 } }],
        'meta' => { 'all_count' => 7 } }
    end

    def medir(medida, dados = corpo)
      described_class.new(medida).de(dados)
    end

    it 'conta itens, com e sem filtro', :aggregate_failures do
      expect(medir({ 'tipo' => 'contagem' }).valor).to eq(2)
      expect(medir({ 'tipo' => 'contagem', 'onde' => { 'ok' => true } }).valor).to eq(1)
    end

    it 'soma e acha o maior, dizendo qual item', :aggregate_failures do
      expect(medir({ 'tipo' => 'soma', 'campo' => 'disparos.hora' }).valor).to eq(12)
      maior = medir({ 'tipo' => 'maior', 'campo' => 'disparos.hora' })
      expect([maior.valor, maior.item_id]).to eq([9, 2])
    end

    it 'lê um número da resposta, e a lista pode vir na raiz ou em outra chave', :aggregate_failures do
      expect(medir({ 'tipo' => 'valor', 'campo' => 'meta.all_count' }).valor).to eq(7)
      expect(medir({ 'tipo' => 'contagem' }, [{ 'id' => 1 }]).valor).to eq(1)
      expect(medir({ 'tipo' => 'contagem' }, { 'decisores' => [{ 'id' => 1 }, { 'id' => 2 }] }).valor).to eq(2)
    end

    it 'sem o que a medida pede, devolve nil', :aggregate_failures do
      expect(medir({ 'tipo' => 'valor', 'campo' => 'meta.nao_tem' })).to be_nil
      expect(medir({ 'tipo' => 'contagem' }, { 'meta' => {} })).to be_nil
    end
  end

  describe Autonomia::Guide::Triagem do
    let(:conta) { create(:account) }
    let(:jev_url) { 'https://api.typesafe.ai/v1/systemone' }
    let(:vigia) do
      Autonomia::Guide::Vigia.new(account: conta, nome: 'Conexão caída', gravidade: 'urgente', gatilho: { 'acima_de' => 0 })
    end
    let(:outra) { Autonomia::Guide::Vigia.new(account: conta, nome: 'Decisões paradas', gravidade: 'agir', gatilho: { 'acima_de' => 0 }) }

    before { allow(TypesafeAi::Config).to receive_messages(api_key: 'ts_test_key_not_real', model: 'jev-1.13.0', configured?: true) }

    def responder(answers, model: 'jev-1.13.0')
      stub_request(:post, jev_url).to_return(status: 200, body: { model: model, usage: { input_tokens: 10, output_tokens: 1 },
                                                                  answers: answers }.to_json)
    end

    def escolha(valor) = { type: 'choice', choice: valor, confidence: 0.8 }

    it 'uma ida, só com números e nomes de vigia; "mesmo assunto" só com mais de um sinal', :aggregate_failures do
      responder({ avisar: escolha('sim'), gravidade: escolha('info') })

      veredito = described_class.new(account: conta).classificar([{ vigia: vigia, valor: 2, media: nil }])

      expect(veredito.to_h).to eq(avisar: true, gravidade: 'info', mesmo_assunto: false)
      expect(a_request(:post, jev_url).with { |pedido| JSON.parse(pedido.body)['questions'].keys == %w[avisar gravidade] })
        .to have_been_made.once
    end

    it 'com dois sinais pergunta também se são do mesmo assunto' do
      responder({ avisar: escolha('sim'), gravidade: escolha('agir'), mesmo_assunto: escolha('sim') })

      veredito = described_class.new(account: conta).classificar([{ vigia: vigia, valor: 2 }, { vigia: outra, valor: 1 }])

      expect(veredito.mesmo_assunto).to be(true)
    end

    it 'resposta fora do combinado vale a gravidade mais alta das vigias, e avisa', :aggregate_failures do
      responder({ avisar: escolha('talvez'), gravidade: escolha('info') })

      veredito = described_class.new(account: conta).classificar([{ vigia: vigia, valor: 2 }, { vigia: outra, valor: 1 }])

      expect(veredito.to_h).to eq(avisar: true, gravidade: 'urgente', mesmo_assunto: false)
    end

    it 'cota mensal esgotada: não chama o Jev' do
      allow(described_class).to receive(:cota_esgotada?).and_return(true)

      described_class.new(account: conta).classificar([{ vigia: vigia, valor: 2 }])

      expect(a_request(:post, jev_url)).not_to have_been_made
    end
  end
end
# rubocop:enable RSpec/DescribeClass
