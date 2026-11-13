require 'rails_helper'

# E4 (#2897): o tipo de cada ramo escrito na planilha. Quem decide é o modelo (aqui, um dublê), uma vez por ramo
# distinto; o que a importação ou a conta já resolveram não é perguntado de novo. Dados fictícios.
RSpec.describe Carteira::Trazer::TipoDoRamo, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:pessoa) { create(:contact, account: account) }
  let(:importacao) { create_contact_import(account: account, user: user, content: "Nome;Celular\nAna Albuquerino;11987650001\n") }
  let(:do_modelo) { { 'automóvel' => 'auto', 'vida' => 'vida', 'pet' => 'outro' } }
  let(:pergunta) { instance_double(Carteira::Trazer::PerguntaDoRamo) }

  before { allow(pergunta).to receive(:call) { |ramos| do_modelo.slice(*ramos) } }

  def tipos
    described_class.new(importacao.reload, pergunta: pergunta)
  end

  # Como a leitura da planilha guarda o que resolveu.
  def guardar(mapa)
    importacao.update!(options: importacao.options.merge('trazer' => { 'tipos_do_ramo' => mapa }))
  end

  it 'pergunta ao modelo só os ramos distintos, sem espaço sobrando nem diferença de maiúscula' do
    mapa = tipos.resolver(['Automóvel', ' AUTOMÓVEL ', 'Vida', '', nil, 'vida'])

    expect(pergunta).to have_received(:call).with(%w[automóvel vida]).once
    expect(mapa.values).to eq(%w[auto vida])
  end

  it 'guarda o resumo do ramo, nunca o texto: o que a célula dizia não fica nas opções da importação' do
    mapa = tipos.resolver(%w[Automóvel Vida])
    guardar(mapa)

    expect(mapa.keys.map(&:length)).to eq([64, 64])
    # O que fica guardado é { resumo => tipo }: o tipo é um dos cinco da carteira, e o ramo não aparece.
    expect(mapa.keys.join.downcase).not_to include('autom', 'vida')
    expect(importacao.reload.options.to_json.downcase).not_to include('autom')
    expect(mapa.keys.first).not_to eq(described_class.chave(importacao.id + 1, 'Automóvel'))
    expect(['Automóvel', ' automóvel', 'VIDA', 'Náutico', '', nil].map { |ramo| tipos.de(ramo) }).to eq(%w[auto auto vida outro outro outro])
  end

  it 'o ramo que esta importação já resolveu não volta ao modelo' do
    guardar(tipos.resolver(%w[Automóvel]))
    guardar(tipos.resolver(%w[Automóvel Vida]))

    mapa = tipos.resolver(%w[AUTOMÓVEL vida])

    expect(pergunta).to have_received(:call).with(%w[automóvel]).once
    expect(pergunta).to have_received(:call).with(%w[vida]).once
    expect(pergunta).to have_received(:call).twice
    expect(mapa.values).to eq(%w[auto vida])
  end

  it 'o ramo que a conta já tem resolvido nas apólices dela não chama o modelo: vale o tipo mais frequente, e "outro" não conta' do
    2.times { criar_apolice(pessoa, ramo_original: 'Frota Leve', tipo: 'empresarial') }
    criar_apolice(pessoa, ramo_original: 'FROTA LEVE ', tipo: 'auto')
    criar_apolice(pessoa, ramo_original: 'Pet', tipo: 'outro')
    criar_apolice(create(:contact, account: create(:account)), ramo_original: 'Vida', tipo: 'residencial')

    mapa = tipos.resolver(['frota leve', 'Pet', 'Vida'])
    guardar(mapa)

    expect(pergunta).to have_received(:call).with(%w[pet vida]).once
    expect(['Frota Leve', 'Pet', 'Vida'].map { |ramo| tipos.de(ramo) }).to eq(%w[empresarial outro vida])
  end

  it 'sem resposta do modelo, o ramo não é guardado: entra como "outro" e é perguntado de novo na próxima leitura' do
    allow(pergunta).to receive(:call).and_return({})

    mapa = tipos.resolver(%w[Automóvel])
    guardar(mapa)

    expect([mapa, tipos.de('Automóvel')]).to eq([{}, 'outro'])
  end

  it 'a coluna errada não vai ao modelo: e-mail, número comprido e texto longo ficam de fora, e coluna com valores demais também' do
    tipos.resolver(['ana.albuquerino@exemplo.com.br', '11987650001', 'x' * 61, '0531 - Automóvel', 'Vida'])
    tipos.resolver((1..81).map { |numero| "valor #{numero}" })

    expect(pergunta).to have_received(:call).with(['0531 - automóvel', 'vida']).once
    expect(pergunta).to have_received(:call).with([]).once
  end
end
