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
  # O texto da posição 09.01, que entra na descrição de cada código dela (revisão do #2917, 6).
  let(:cafe) { 'Café, mesmo torrado ou descafeinado; cascas e películas de café; sucedâneos do café que contenham café em qualquer proporção' }

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

  # O texto de cada busca feita à fonte ("café torrado", "0901").
  def buscas_feitas
    pedidos.map { |uri| CGI.unescape(URI(uri).query.to_s.delete_prefix('search=')) }
  end

  def buscar(busca)
    executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => busca)
  end

  def codigo(codigo)
    executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => codigo)
  end

  # Revisão do #2917 (9): o formato guardado da NCM mudou, e só o cache dela deixa de valer; o global continua.
  it 'a versao do cache muda so na NCM' do
    expect(Autonomia::FerramentasProntas::Cache::VERSAO).to eq('v2')
    expect(ncm::FONTE.consultas.map { |consulta| consulta.chave_do_cache({}) }).to all(include('versao_do_cache' => ncm::VERSAO_DO_CACHE))
  end

  describe 'buscar' do
    it '"cafe torrado": o grupo abre nos codigos da nota, com a descricao completa, em uma chamada a mais' do
      fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      dados = buscar('café torrado')['dados']

      expect(dados).to eq(
        'busca' => 'café torrado', 'total' => 2,
        'itens' => [{ 'codigo' => '0901.21.00', 'descricao' => "#{cafe}, café torrado, não descafeinado", 'vigente_desde' => '2022-04-01' },
                    { 'codigo' => '0901.22.00', 'descricao' => "#{cafe}, café torrado, descafeinado", 'vigente_desde' => '2022-04-01' }]
      )
      expect(pedidos.size).to eq(2)
    end

    # Revisão do #2917 (5): cada item passa uma vez só pelo Nokogiri (antes eram umas 10 passagens por item).
    it 'cada item da resposta e lido uma vez so' do
      allow(Nokogiri::HTML5).to receive(:fragment).and_call_original
      fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      buscar('café torrado')

      expect(Nokogiri::HTML5).to have_received(:fragment).exactly(1 + real('ncm_busca_0901.json').size).times
    end

    # Revisão do #2917 (BAIXO): o item fora do formato na chamada a mais fica de lado, e a consulta segue.
    it 'item sem descricao valida na chamada a mais nao derruba a consulta' do
      fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))
      fonte_responde("#{api}?search=0901", real('ncm_busca_0901.json') + [{ 'codigo' => '0901.23.00', 'descricao' => '<br>' }])

      dados = buscar('café torrado')['dados']

      expect(dados['itens'].pluck('codigo')).to eq(%w[0901.21.00 0901.22.00])
    end

    # Revisão do #2917 (2): o capítulo (2 dígitos) nunca abre. "veículos" abria o 86 (ferrovia) e "máquinas" o 85 (980
    # itens, 206 KB, 2,2 s). Os candidatos a abrir são os grupos de 4 a 7 dígitos.
    it 'o capitulo nunca abre: "veiculos" e "maquinas" reais' do
      stub_request(:get, api).with(query: hash_including({})).to_return(body: '[]', headers: { 'Content-Type' => 'application/json' })
      fonte_responde("#{api}?search=ve%C3%ADculos", fixture('ncm_busca_veiculos.json'))
      fonte_responde("#{api}?search=m%C3%A1quinas", fixture('ncm_busca_maquinas.json'))

      expect(buscar('veículos')['situacao']).to eq('encontrado')
      expect(buscar('máquinas')['situacao']).to eq('encontrado')
      expect(buscas_feitas.select { |termo| termo.length < ncm::POSICAO }).to eq([])
    end

    # Revisão do #2917 (3): escolher o produto que o cliente quis dizer é do modelo, não de ranking de palavra (regra do
    # Rodrigo). "celular" empata a marcenaria (44.18, painéis celulares) com os telefones (85.17): nada abre.
    it '"celular" real: grupos empatados nao abrem, e o modelo e orientado a buscar pelo codigo do grupo' do
      fonte_responde("#{api}?search=celular", fixture('ncm_busca_celular.json'))

      dados = buscar('celular')['dados']

      expect(dados['observacao']).to eq(ncm::ESCOLHA_O_GRUPO)
      expect(dados['itens'].pluck('codigo')).to include('44.18', '85.17')
      expect(buscas_feitas).to eq(['celular'])
    end

    it '"cafe" real: o grupo de dentro conta como o de fora, e so a posicao 09.01 abre' do
      fonte_responde("#{api}?search=caf%C3%A9", fixture('ncm_busca_cafe.json'))
      pela_posicao = fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      dados = buscar('café')['dados']

      codigos = dados['itens'].pluck('codigo')
      expect(codigos).to include('0901.11.10', '0901.12.00', '0901.21.00', '0901.22.00', '0901.90.00', '21.01')
      expect(codigos).not_to include('09.01', '0901.1', '0901.2')
      expect(dados).not_to have_key('observacao')
      expect(pela_posicao).to have_been_made.once
    end

    it 'as observacoes cabem inteiras no texto que vai ao modelo, e nenhuma manda buscar um capitulo' do
      textos = [format(ncm::SEM_OS_DA_NOTA, grupo: '8517.62.6'), ncm::ESCOLHA_O_GRUPO]

      expect(textos.map(&:length)).to all(be <= Autonomia::FerramentasProntas::Resposta::MAX_TEXTO)
      expect(ncm::ESCOLHA_O_GRUPO).to include('4 dígitos ou mais')
    end

    # Revisão do #2917 (1): o texto vai ao modelo com teto (`Resposta::MAX_TEXTO`, 160) e o corte comia o texto do
    # próprio código: "brinquedos" voltava 20 códigos com 3 descrições. O texto próprio cabe sempre inteiro.
    it '"brinquedos" real: cada codigo com a sua descricao, inteira no fim, dentro do teto' do
      fonte_responde("#{api}?search=brinquedos", fixture('ncm_busca_brinquedos.json'))
      fonte_responde("#{api}?search=9503", fixture('ncm_busca_9503.json'))
      proprios = (real('ncm_busca_brinquedos.json') + real('ncm_busca_9503.json'))
                 .to_h { |dado| [dado['codigo'], ncm::Descricao.limpa(ncm.texto(dado['descricao'])).downcase] }

      da_nota = buscar('brinquedos')['dados']['itens'].select { |item| item['codigo'].delete('.').length == 8 }

      expect(da_nota.size).to be > 3
      expect(da_nota.pluck('descricao').uniq.size).to eq(da_nota.size)
      expect(da_nota.pluck('descricao').map(&:length)).to all(be <= Autonomia::FerramentasProntas::Resposta::MAX_TEXTO)
      expect(da_nota).to all(satisfy { |item| item['descricao'].downcase.end_with?(proprios.fetch(item['codigo'])) })
    end

    it '"parafuso" continua bom: os parafusos primeiro, com a descricao completa, e a posicao 73.18 aberta' do
      fonte_responde("#{api}?search=parafuso", fixture('ncm_busca_parafuso.json'))
      fonte_responde("#{api}?search=7318", fixture('ncm_busca_7318.json'))

      dados = buscar('parafuso')['dados']

      primeiros = dados['itens'].first(4)
      expect(primeiros.pluck('codigo')).to eq(%w[7318.14.00 7415.33.00 7318.12.00 7318.15.00])
      expect(primeiros.pluck('descricao')).to eq(
        ['Parafusos, pinos ou pernos, roscados, porcas … e artigos semelhantes, de ferro fundido, ferro ou aço, artigos roscados, ' \
         'parafusos autoperfurantes',
         'Tachas, pregos, percevejos, escápulas (pregos para tacos) e … (incluindo as de pressão), e artigos semelhantes, de cobre, ' \
         'parafusos; pinos ou pernos e porcas',
         'Parafusos, pinos ou pernos, roscados, porcas … e artigos semelhantes, de ferro fundido, ferro ou aço, artigos roscados, ' \
         'outros parafusos para madeira',
         'Parafusos, pinos ou pernos … de ferro fundido, ferro ou aço, artigos roscados, outros parafusos e pinos ou pernos, mesmo ' \
         'com as porcas e arruelas (anilhas)']
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
                          'itens' => [{ 'codigo' => '0901.2', 'descricao' => "#{cafe}, café torrado", 'vigente_desde' => '2022-04-01' }])
    end

    it 'o prazo acaba antes da segunda chamada: o que veio, com a observacao, e fora do cache' do
      allow(Autonomia::FerramentasProntas::ClienteHttp).to receive(:agora).and_return(0.0, 0.0, 100.0)
      fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))

      dados = buscar('café torrado')['dados']

      expect(dados).to eq('busca' => 'café torrado', 'total' => 1,
                          'itens' => [{ 'codigo' => '0901.2', 'descricao' => 'Café torrado', 'vigente_desde' => '2022-04-01' }],
                          'observacao' => format(ncm::SEM_OS_DA_NOTA, grupo: '0901.2'))
      expect(a_request(:get, "#{api}?search=0901")).not_to have_been_made
      expect(ncm::BrasilApi.validade_da_resposta(dados)).to eq(0)
    end

    it 'a busca pela propria posicao ja traz os filhos: sem chamada a mais, so os codigos da nota' do
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      dados = buscar('0901')['dados']

      expect(dados['itens']).to include(
        { 'codigo' => '0901.12.00', 'descricao' => "#{cafe}, café não torrado, descafeinado", 'vigente_desde' => '2022-04-01' },
        { 'codigo' => '0901.90.00', 'descricao' => "#{cafe}, outros", 'vigente_desde' => '2022-04-01' }
      )
      expect(dados['itens'].pluck('codigo')).to all(satisfy { |codigo| codigo.delete('.').length == 8 })
      expect(dados['total']).to eq(6)
      expect(pedidos.size).to eq(1)
    end
  end

  # Revisão do #2917 (6): com subposição no meio, a posição saía e levava o material junto (7318.14.00 perdia "de ferro
  # ou aço"; 7415.33.00, "de cobre"). A posição entra sempre que veio.
  describe 'a descricao completa leva a posicao, com o material' do
    def completa(codigo, arquivo)
      niveis = ncm.niveis(real(arquivo))
      ncm::Descricao.completa(niveis.find { |nivel| nivel.codigo == codigo }, ncm::Descricao.indice(niveis))
    end

    it 'o parafuso de aco e o de cobre' do
      expect(completa('7318.14.00', 'ncm_busca_7318.json'))
        .to start_with('Parafusos, pinos ou pernos').and include('de ferro fundido, ferro ou aço')
        .and end_with('artigos roscados, parafusos autoperfurantes')
      expect(completa('7415.33.00', 'ncm_busca_parafuso.json')).to include('de cobre').and end_with('parafusos; pinos ou pernos e porcas')
    end
  end

  describe 'codigo' do
    # Revisão do #2917 (4): uma chamada só, pela posição, que já traz o código e os níveis de cima.
    it '0901.21.00: a descricao completa, numa chamada so pela posicao' do
      pela_posicao = fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      expect(codigo('0901.21.00')['dados'])
        .to eq('codigo' => '0901.21.00', 'descricao' => "#{cafe}, café torrado, não descafeinado", 'vigente_desde' => '2022-04-01')
      expect(pela_posicao).to have_been_made.once
      expect(a_request(:get, "#{api}/09012100")).not_to have_been_made
    end

    it 'codigo de 8 digitos que nao esta na posicao: nao encontrado' do
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      expect(codigo('0901.99.99')['situacao']).to eq('nao_encontrado')
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

  # Revisão do #2891 (f e g).
  describe 'o HTML da descricao' do
    let(:dado) { { codigo: '73.18', descricao: '', data_inicio: '2022-04-01' } }

    it 'a quebra de linha vira espaco: as duas linhas nao colam' do
      fonte_responde("#{api}/7318", dado.merge(descricao: 'Parafusos de aço<br>com porca'))

      expect(codigo('7318')['dados']['descricao']).to eq('Parafusos de aço com porca')
    end

    it 'descricao feita so de tags: resposta invalida, e o agente ouve "nao consegui"' do
      fonte_responde("#{api}/7318", dado.merge(descricao: '<br><i></i>'))

      expect(codigo('7318')['situacao']).to eq('nao_consegui_consultar')
      expect(uso.motivos).to eq('brasilapi.resposta_invalida' => 1)
    end
  end
end
