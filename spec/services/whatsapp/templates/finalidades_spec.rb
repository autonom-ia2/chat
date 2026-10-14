require 'rails_helper'

# Os prontos de cada finalidade (#1518) passam pelas mesmas regras da tela de Modelos e do envio, e pelo que a Meta pede
# do corpo: variável nunca no começo nem no fim, numeradas em ordem a partir de 1 e com um exemplo para cada uma.
RSpec.describe Whatsapp::Templates::Finalidades do
  let(:prontos) { described_class.prontos }

  def body_of(pronto)
    pronto.corpo[:components].find { |component| component[:type] == 'BODY' }
  end

  it 'tem os 6 prontos da cobrança: antes, no dia e depois do vencimento, com e sem valor' do
    variantes = %i[antes no_dia depois].product([true, false])
    found = variantes.map { |momento, com_valor| described_class.pronto(:cobranca_vencimento, momento: momento, com_valor: com_valor) }

    expect(found.map(&:nome).uniq.size).to eq(6)
    expect(found.map(&:dono).uniq).to eq(['cobranca'])
    expect(found.map(&:idioma).uniq).to eq(['pt_BR'])
  end

  it 'aceita a finalidade e o momento como texto' do
    expect(described_class.pronto('cobranca_vencimento', momento: 'no_dia', com_valor: false).nome)
      .to eq(described_class.pronto(:cobranca_vencimento, momento: :no_dia, com_valor: false).nome)
  end

  it 'recusa finalidade ou variante que não existe' do
    expect { described_class.pronto(:boas_vindas) }.to raise_error(described_class::Desconhecida)
    expect { described_class.pronto(:cobranca_vencimento, momento: :ontem, com_valor: true) }.to raise_error(described_class::Desconhecida)
    expect { described_class.pronto(:cobranca_vencimento, momento: :antes) }.to raise_error(described_class::Desconhecida)
  end

  it 'só a variante com valor pede o valor' do
    com = described_class.pronto(:cobranca_vencimento, momento: :antes, com_valor: true)
    sem = described_class.pronto(:cobranca_vencimento, momento: :antes, com_valor: false)

    expect(com.campos).to eq('1' => 'cliente.primeiro_nome', '2' => 'negocio.valor', '3' => 'negocio.titulo', '4' => 'negocio.prazo')
    expect(sem.campos).to eq('1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo', '3' => 'negocio.prazo')
  end

  it 'todo pronto é UTILITY e passa na conferência da Meta (SubmitFormat) e na do envio (SendableFormat)' do
    prontos.each do |pronto|
      template = pronto.corpo.deep_stringify_keys
      expect(template['category']).to eq('UTILITY')
      expect(Whatsapp::Templates::SubmitFormat.problems(template)).to eq([]), pronto.nome
      expect(Whatsapp::Templates::SendableFormat.sendable?(template)).to be(true), pronto.nome
    end
  end

  it 'todo campo é uma chave do catálogo de campos (quem envia sabe de onde vem o valor)' do
    prontos.flat_map { |pronto| pronto.campos.values }.uniq.each do |campo|
      expect(TemplateFields::Catalog.known?(campo)).to be(true), campo
    end
  end

  it 'nenhum corpo começa ou termina com variável' do
    prontos.each do |pronto|
      text = body_of(pronto)[:text]
      expect(text.lstrip.start_with?('{{')).to be(false), pronto.nome
      expect(text.rstrip.end_with?('}}')).to be(false), pronto.nome
    end
  end

  it 'as variáveis vão de 1 em diante, na ordem do texto, cada uma com exemplo e com campo' do
    prontos.each do |pronto|
      body = body_of(pronto)
      numbers = body[:text].split('{{').drop(1).map { |piece| piece.split('}}').first }
      expected = (1..pronto.campos.size).map(&:to_s)

      expect(numbers).to eq(expected), pronto.nome
      expect(pronto.campos.keys).to eq(expected), pronto.nome
      examples = body.dig(:example, :body_text, 0)
      expect(examples.size).to eq(expected.size), pronto.nome
      expect(examples).to all(be_present)
    end
  end

  it 'reconhece o dono pelo nome do pronto' do
    expect(described_class.dono_de(prontos.first.nome)).to eq('cobranca')
    expect(described_class.dono_de('boas_vindas')).to be_nil
  end

  it 'os textos da cobrança falam de pagamento, sem "negócio" nem "compra" (pedido do Multifunnel)' do
    prontos.select { |pronto| pronto.finalidade == 'cobranca_vencimento' }.each do |pronto|
      expect(pronto.texto).to include('pagamento')
      expect(pronto.texto.downcase).not_to include('negócio')
      expect(pronto.texto.downcase).not_to include('compra')
    end
  end

  # Estrutura para o lembrete do agendamento (#1524): ainda sem finalidade real, provada com uma de teste.
  describe 'pronto com botões' do
    let(:com_botoes) do
      { 'teste_botoes' => { dono: 'agendamento', opcoes: [], variantes: { [] => {
        nome: 'teste_botoes_v1', amigavel: 'Teste', campos: %w[cliente.primeiro_nome negocio.prazo],
        texto: 'Olá, {{1}}! Seu horário é {{2}}. Use os botões abaixo.',
        botoes: [{ tipo: 'url', texto: 'Ver meu horário', url: 'https://chat.hub2you.ai/b/{{1}}', campo: 'horario.link_codigo',
                   exemplo: 'AB3K9QXZ' },
                 { tipo: 'quick_reply', texto: 'Parar avisos', payload: 'stop_notices' }]
      } } } }
    end

    before { stub_const("#{described_class}::CATALOGO", described_class::CATALOGO.merge(com_botoes)) }

    it 'manda à Meta o URL com exemplo e a resposta rápida, e passa nas duas conferências' do
      template = described_class.pronto(:teste_botoes).corpo.deep_stringify_keys
      buttons = template['components'].find { |component| component['type'] == 'BUTTONS' }['buttons']

      expect(buttons).to eq([{ 'type' => 'URL', 'text' => 'Ver meu horário', 'url' => 'https://chat.hub2you.ai/b/{{1}}',
                               'example' => ['https://chat.hub2you.ai/b/AB3K9QXZ'] },
                             { 'type' => 'QUICK_REPLY', 'text' => 'Parar avisos' }])
      expect(Whatsapp::Templates::SubmitFormat.problems(template)).to eq([])
      expect(Whatsapp::Templates::SendableFormat.sendable?(template)).to be(true)
    end

    it 'diz ao envio a posição, o tipo e o campo ou payload de cada botão' do
      expect(described_class.pronto(:teste_botoes).botoes_do_envio).to eq(
        [{ 'indice' => 0, 'tipo' => 'url', 'campo' => 'horario.link_codigo' },
         { 'indice' => 1, 'tipo' => 'quick_reply', 'payload' => 'stop_notices' }]
      )
    end

    it 'pronto sem botões não manda o componente de botões' do
      expect(prontos.first.corpo[:components].map { |component| component[:type] }).to eq(['BODY'])
      expect(prontos.first.botoes_do_envio).to eq([])
    end
  end
end
