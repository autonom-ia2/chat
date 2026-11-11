require 'rails_helper'

# #2858 — a NCM achava o grupo e não o código da nota (teste do Rodrigo em produção, 11/11/2026): "café torrado" devolvia
# só "0901.2 | - Café torrado:", e a tela mostrava "Café torrado:" e o código 0901.2, que não serve na nota. As respostas
# são as reais da BrasilAPI de 11/11/2026 (`spec/fixtures/ferramentas_prontas/ncm_*.json`), pelo caminho real (a
# `Execucao` da pronta de um agente), com o WebMock no lugar da fonte.
RSpec.describe Autonomia::FerramentasProntas::Fontes do
  let(:ncm) { Autonomia::FerramentasProntas::Fontes::Ncm }
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:ferramenta) { incluir_pronta('ncm', conta: account, agente: agent) }
  let(:api) { 'https://brasilapi.com.br/api/ncm/v1' }
  let(:uso) { Autonomia::FerramentasProntas::Uso.sole }

  before do
    resolver_hosts_das_prontas
    account.enable_features!(Autonomia::FerramentasProntas::FLAG, Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
  end

  around { |example| travel_to(Time.zone.parse('2026-11-11 10:00')) { example.run } }

  def fixture(nome)
    Rails.root.join('spec/fixtures/ferramentas_prontas', nome).read
  end

  def real(nome)
    JSON.parse(fixture(nome))
  end

  def pedidos
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |assinatura| assinatura.uri.to_s }
  end

  def buscar(busca)
    executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => busca)
  end

  def codigo(codigo)
    executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => codigo)
  end

  describe 'buscar' do
    it '"cafe torrado": o grupo abre nos codigos da nota, com a descricao completa, em uma chamada a mais' do
      fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      dados = buscar('café torrado')['dados']

      expect(dados).to eq(
        'busca' => 'café torrado', 'total' => 2,
        'itens' => [{ 'codigo' => '0901.21.00', 'descricao' => 'Café torrado, não descafeinado', 'vigente_desde' => '2022-04-01' },
                    { 'codigo' => '0901.22.00', 'descricao' => 'Café torrado, descafeinado', 'vigente_desde' => '2022-04-01' }]
      )
      expect(pedidos.size).to eq(2)
    end

    it '"parafuso" continua bom: os parafusos primeiro, com a descricao completa, e a posicao 73.18 aberta' do
      fonte_responde("#{api}?search=parafuso", fixture('ncm_busca_parafuso.json'))
      fonte_responde("#{api}?search=7318", fixture('ncm_busca_7318.json'))

      dados = buscar('parafuso')['dados']

      expect(dados['itens'].first(4)).to eq(
        [{ 'codigo' => '7318.14.00', 'descricao' => 'Artigos roscados, parafusos autoperfurantes', 'vigente_desde' => '2022-04-01' },
         { 'codigo' => '7415.33.00', 'descricao' => 'Parafusos; pinos ou pernos e porcas', 'vigente_desde' => '2022-04-01' },
         { 'codigo' => '7318.12.00', 'descricao' => 'Artigos roscados, outros parafusos para madeira', 'vigente_desde' => '2022-04-01' },
         { 'codigo' => '7318.15.00',
           'descricao' => 'Artigos roscados, outros parafusos e pinos ou pernos, mesmo com as porcas e arruelas (anilhas)',
           'vigente_desde' => '2022-04-01' }]
      )
      expect(dados['total']).to eq(20)
      expect(dados).not_to have_key('mostrando')
      expect(dados['itens'].pluck('codigo')).not_to include('73.18')
      expect(dados['itens'].pluck('descricao').join).not_to include(' -', ':')
      expect(pedidos.size).to eq(2)
    end

    it 'grupo sem filhos de 8 digitos: fica o grupo, com a descricao limpa' do
      sem_os_da_nota = real('ncm_busca_0901.json').reject { |dado| dado['codigo'].delete('.').length == 8 }
      fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))
      fonte_responde("#{api}?search=0901", sem_os_da_nota)

      dados = buscar('café torrado')['dados']

      expect(dados).to eq('busca' => 'café torrado', 'total' => 1,
                          'itens' => [{ 'codigo' => '0901.2', 'descricao' => 'Café torrado', 'vigente_desde' => '2022-04-01' }])
    end

    it 'o prazo acaba antes da segunda chamada: o que veio, com a observacao, e fora do cache' do
      allow(Autonomia::FerramentasProntas::ClienteHttp).to receive(:agora).and_return(0.0, 0.0, 100.0)
      fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))

      dados = buscar('café torrado')['dados']

      expect(dados).to eq('busca' => 'café torrado', 'total' => 1,
                          'itens' => [{ 'codigo' => '0901.2', 'descricao' => 'Café torrado', 'vigente_desde' => '2022-04-01' }],
                          'observacao' => ncm::SEM_OS_DA_NOTA)
      expect(a_request(:get, "#{api}?search=0901")).not_to have_been_made
      expect(ncm::BrasilApi.validade_da_resposta(dados)).to eq(0)
    end

    it 'a busca pela propria posicao ja traz os filhos: sem chamada a mais, so os codigos da nota' do
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      dados = buscar('0901')['dados']

      expect(dados['itens']).to include(
        { 'codigo' => '0901.11.10', 'descricao' => 'Café não torrado, não descafeinado, em grão', 'vigente_desde' => '2022-04-01' },
        { 'codigo' => '0901.12.00', 'descricao' => 'Café não torrado, descafeinado', 'vigente_desde' => '2022-04-01' },
        { 'codigo' => '0901.90.00',
          'descricao' => 'Café, mesmo torrado ou descafeinado; cascas e películas de café; sucedâneos do café que contenham ' \
                         'café em qualquer proporção, outros',
          'vigente_desde' => '2022-04-01' }
      )
      expect(dados['itens'].pluck('codigo')).to all(satisfy { |codigo| codigo.delete('.').length == 8 })
      expect(dados['total']).to eq(6)
      expect(pedidos.size).to eq(1)
    end
  end

  describe 'codigo' do
    it '0901.21.00: a descricao completa, pela posicao do codigo' do
      fonte_responde("#{api}/09012100", fixture('ncm_codigo_09012100.json'))
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      expect(codigo('0901.21.00')['dados'])
        .to eq('codigo' => '0901.21.00', 'descricao' => 'Café torrado, não descafeinado', 'vigente_desde' => '2022-04-01')
    end

    it 'o prazo acaba antes da segunda chamada: a descricao do ultimo nivel, com a observacao' do
      allow(Autonomia::FerramentasProntas::ClienteHttp).to receive(:agora).and_return(0.0, 0.0, 100.0)
      fonte_responde("#{api}/09012100", fixture('ncm_codigo_09012100.json'))

      dados = codigo('0901.21.00')['dados']

      expect(dados).to eq('codigo' => '0901.21.00', 'descricao' => 'Não descafeinado', 'vigente_desde' => '2022-04-01',
                          'observacao' => ncm::SO_O_ULTIMO_NIVEL)
      expect(ncm::BrasilApi.validade_da_resposta(dados)).to eq(0)
    end

    it 'capitulo (2) e posicao (4): o texto inteiro deles, sem chamada a mais' do
      fonte_responde("#{api}/0901", real('ncm_busca_0901.json').first)
      fonte_responde("#{api}/09", { codigo: '09', descricao: 'Café, chá, mate e especiarias.', data_inicio: '2022-04-01' })

      expect(codigo('0901')['dados']['descricao']).to eq(
        'Café, mesmo torrado ou descafeinado; cascas e películas de café; sucedâneos do café que contenham café em ' \
        'qualquer proporção.'
      )
      expect(codigo('09')['dados']['descricao']).to eq('Café, chá, mate e especiarias.')
      expect(pedidos.size).to eq(2)
    end
  end
end
