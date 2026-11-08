require 'rails_helper'

# #2034: o cérebro do follow-up escreve ao cliente com o vocabulário da conta (pacote do servidor, #1550). A linha entra
# nas instruções dos três envios ao cliente (follow-up, retorno combinado e lembrete de Atender), antes do tom do dono.
# O lembrete interno para a equipe e a conta sem pacote ficam como sempre foram.
RSpec.describe Crm::Ai::FollowUpComposer, '#instructions' do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:perfil) { 'corretora' }
  let(:account) { create(:account, internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil }) }
  let(:card) { instance_double(Crm::Card, account: account) }
  let(:pacote) { 'true' }

  let(:linha_seguros) do
    'Fale de seguro, apólice e sinistro; chame de cliente só quem já contratou e de segurado só quem tem apólice.'
  end
  let(:linha_corretora) do
    'Fale como a corretora: diga corretor, cotação e apólice; chame de cliente só quem já contratou e de segurado só quem tem apólice.'
  end
  let(:linha_saude) do
    'Fale de plano, vidas, titular e dependentes, operadora, boleto e reembolso; ' \
      'chame de cliente quem procura ou já tem o plano e nunca diga segurado nem apólice.'
  end

  around do |example|
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: pacote) { example.run }
  ensure
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
  end

  def instructions(card: self.card, **)
    described_class.new(card: card, client: nil, context: {}, **).send(:instructions)
  end

  describe 'nos três envios ao cliente' do
    {
      'follow-up em texto livre' => { mode: :free_form },
      'follow-up com modelo aprovado' => { mode: :choose_template },
      'retorno combinado' => { purpose: :callback },
      'lembrete de Atender' => { purpose: :service }
    }.each do |nome, options|
      it "#{nome}: entra a linha da corretora" do
        expect(instructions(**options)).to include(linha_corretora)
      end
    end
  end

  describe 'por perfil da conta' do
    todas_as_linhas = %i[linha_seguros linha_corretora linha_saude]
    {
      'corretora' => :linha_corretora,
      'seguradora' => :linha_seguros,
      'insurtech' => :linha_seguros,
      'saude_beneficios' => :linha_saude
    }.each do |outro_perfil, linha|
      describe "com o perfil #{outro_perfil}" do
        let(:perfil) { outro_perfil }

        it 'entra só a linha dele' do
          texto = instructions
          esperada = send(linha)
          outras = todas_as_linhas.map { |nome| send(nome) } - [esperada]

          expect(texto).to include(esperada)
          expect(outras.none? { |outra| texto.include?(outra) }).to be(true)
        end
      end
    end
  end

  it 'vem antes do tom escrito pelo dono, que segue valendo por cima' do
    texto = instructions(tone_instructions: 'Seja breve e use "você".')

    expect(texto).to include('INSTRUÇÕES DE TOM/MARCA (siga rigorosamente): Seja breve e use "você".')
    expect(texto.index(linha_corretora)).to be < texto.index('INSTRUÇÕES DE TOM/MARCA')
  end

  it 'não entra no lembrete interno para a equipe' do
    expect(instructions(mode: :reminder)).not_to include(linha_corretora)
  end

  describe 'sem pacote, o texto é o de sempre' do
    let(:sem_pacote) { described_class.new(card: nil, client: nil, context: {}) }
    let(:tom_do_dono) { 'INSTRUÇÕES DE TOM/MARCA (siga rigorosamente): Seja breve.' }

    describe 'com o interruptor de pacotes desligado' do
      let(:pacote) { nil }

      it 'a linha do tom do dono é a de sempre, sem linha em branco antes' do
        expect(described_class.new(card: card, client: nil, context: {}, tone_instructions: 'Seja breve.')
          .send(:tone_instructions_line)).to eq(tom_do_dono)
      end

      it 'não muda nenhuma instrução' do
        servico = described_class.new(card: nil, client: nil, context: {}, purpose: :service)

        expect(instructions).to eq(sem_pacote.send(:instructions))
        expect(instructions(purpose: :service)).to eq(servico.send(:instructions))
      end
    end

    describe 'em conta fora do nicho de seguros' do
      let(:account) { create(:account) }

      it 'a linha do tom do dono é a de sempre, sem linha em branco antes' do
        expect(described_class.new(card: card, client: nil, context: {}, tone_instructions: 'Seja breve.')
          .send(:tone_instructions_line)).to eq(tom_do_dono)
      end

      it 'não muda nenhuma instrução' do
        callback = described_class.new(card: nil, client: nil, context: {}, purpose: :callback)

        expect(instructions).to eq(sem_pacote.send(:instructions))
        expect(instructions(purpose: :callback)).to eq(callback.send(:instructions))
      end
    end
  end
end
