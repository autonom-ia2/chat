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

  # O texto de cada busca feita à fonte, uma vez por busca diferente ("café torrado", "0901").
  def buscas_feitas
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                            .map { |assinatura| CGI.unescape(assinatura.uri.query.to_s.delete_prefix('search=')) }
  end

  def grupo?(item)
    ncm.digitos(item['codigo']).length.between?(ncm::POSICAO, ncm::DA_NOTA - 1)
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

  # Revisão do #2917 (3), regra do Rodrigo ("a IA precisa dar conta"): nenhum ranking nosso escolhe o grupo. A busca
  # por palavra devolve o que a BrasilAPI trouxe, numa chamada só: os códigos da nota com a descrição completa e os
  # grupos (4 a 7 dígitos) com a orientação para o modelo buscar pelo código do grupo que fizer sentido na conversa.
  describe 'buscar por palavra' do
    it '"cafe torrado" real: o grupo vem com a descricao e a orientacao, sem chamada a mais' do
      pela_palavra = fonte_responde("#{api}?search=caf%C3%A9%20torrado", fixture('ncm_busca_cafe_torrado.json'))

      dados = buscar('café torrado')['dados']

      expect(dados).to eq('busca' => 'café torrado', 'total' => 1,
                          'itens' => [{ 'codigo' => '0901.2', 'descricao' => 'Café torrado', 'vigente_desde' => '2022-04-01' }],
                          'observacao' => format(ncm::BUSQUE_O_GRUPO, grupo: '0901.2'))
      expect(pela_palavra).to have_been_made.once
      expect(a_request(:get, "#{api}?search=0901")).not_to have_been_made
    end

    it '"celular" real: os dois grupos vem, e quem escolhe e o modelo' do
      pela_palavra = fonte_responde("#{api}?search=celular", fixture('ncm_busca_celular.json'))

      dados = buscar('celular')['dados']

      expect(dados['itens'].pluck('codigo')).to include('44.18', '85.17', '8517.14', '4418.92.00')
      expect(dados['observacao']).to eq(format(ncm::BUSQUE_O_GRUPO, grupo: dados['itens'].find { |item| grupo?(item) }['codigo']))
      expect(pela_palavra).to have_been_made.once
    end

    # Revisão do #2917 (2): o capítulo (2 dígitos) nunca é oferecido para buscar: a busca pede ao menos 3 letras.
    it '"veiculos" real: o exemplo da orientacao e um grupo de 4 digitos ou mais, nunca o capitulo' do
      pela_palavra = fonte_responde("#{api}?search=ve%C3%ADculos", fixture('ncm_busca_veiculos.json'))

      dados = buscar('veículos')['dados']

      exemplo = dados['itens'].find { |item| grupo?(item) }['codigo']
      expect(dados['observacao']).to eq(format(ncm::BUSQUE_O_GRUPO, grupo: exemplo))
      expect(ncm.digitos(exemplo).length).to be_between(ncm::POSICAO, ncm::DA_NOTA - 1)
      expect(pela_palavra).to have_been_made.once
    end

    it 'sem grupo entre os itens: sem a orientacao' do
      fonte_responde("#{api}?search=parafuso", real('ncm_busca_parafuso.json').select { |dado| ncm.digitos(dado['codigo']).length == 8 })

      expect(buscar('parafuso')['dados']).not_to have_key('observacao')
    end

    it 'as observacoes cabem inteiras no texto que vai ao modelo' do
      textos = [format(ncm::BUSQUE_O_GRUPO, grupo: '8517.62.6'), ncm::CONFIRA]

      expect(textos.map(&:length)).to all(be <= Autonomia::FerramentasProntas::Resposta::MAX_TEXTO)
    end

    it '"parafuso" real: os parafusos primeiro, com o material, numa chamada so' do
      pela_palavra = fonte_responde("#{api}?search=parafuso", fixture('ncm_busca_parafuso.json'))

      dados = buscar('parafuso')['dados']

      primeiros = dados['itens'].first(3)
      expect(primeiros.pluck('codigo')).to eq(%w[7318.14.00 7415.33.00 73.18])
      expect(primeiros.first['descricao']).to include('de ferro fundido, ferro ou aço').and end_with('parafusos autoperfurantes')
      expect(primeiros.second['descricao']).to include('de cobre').and end_with('parafusos; pinos ou pernos e porcas')
      expect(dados['itens'].pluck('descricao').join).not_to include(' -', ':')
      expect(pela_palavra).to have_been_made.once
    end

    # Revisão do #2917 (7): o código da nota que veio sem os níveis de cima tem a descrição relativa ("De parafuso",
    # do 8414.40.20, compressor). Vai marcado, para o modelo conferir com a consulta codigo.
    it 'o codigo da nota sem todos os niveis de cima vai marcado; com eles, nao' do
      fonte_responde("#{api}?search=parafuso", fixture('ncm_busca_parafuso.json'))
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      por_codigo = buscar('parafuso')['dados']['itens'].index_by { |item| item['codigo'] }
      completos = buscar('0901')['dados']['itens']

      expect(por_codigo.values_at('8414.40.20', '7318.14.00', '7415.33.00').pluck('observacao')).to all(eq(ncm::CONFIRA))
      expect(por_codigo['73.18']).not_to have_key('observacao')
      expect(completos).to all(satisfy { |item| !item.key?('observacao') })
    end
  end

  # Revisão do #2917 (B): "0102.29.19 | Outros" com a subposição 0102.29 e sem a posição 01.02 contava como inteira, e o
  # "bovino" da posição sumia. A posição tem de ter vindo; na tabela sem a posição de 4 dígitos (95.03 não existe na
  # BrasilAPI, 404), a subposição "9503.00" faz o papel dela.
  describe 'a descricao inteira pede a posicao' do
    it '"0102.29.19 Outros" real sem o 01.02: vai marcado' do
      vieram = %w[0102.29 0102.29.1 0102.29.19]
      sem_a_posicao = real('ncm_busca_0102.json').select { |dado| vieram.include?(dado['codigo']) }
      fonte_responde("#{api}?search=outros", sem_a_posicao)

      item = buscar('outros')['dados']['itens'].find { |achado| achado['codigo'] == '0102.29.19' }

      expect(item['observacao']).to eq(ncm::CONFIRA)
    end

    it 'com a posicao 01.02, nao; e o 9503.00 vale como posicao' do
      fonte_responde("#{api}?search=outros", fixture('ncm_busca_0102.json'))
      fonte_responde("#{api}?search=brinquedos", fixture('ncm_busca_brinquedos.json'))

      bovinos = buscar('outros')['dados']['itens'].find { |achado| achado['codigo'] == '0102.29.19' }
      brinquedos = buscar('brinquedos')['dados']['itens'].select { |achado| ncm.digitos(achado['codigo']).length == 8 }

      expect(bovinos).not_to have_key('observacao')
      expect(brinquedos).to all(satisfy { |achado| !achado.key?('observacao') })
    end
  end

  # O modelo escolheu o grupo: UMA chamada, pela posição dele (a BrasilAPI não acha "9503.00.3", e "0901.2" vem sem o
  # 09.01, que diz o material), e só os códigos da nota de dentro do grupo.
  describe 'buscar pelo codigo do grupo' do
    it '"0901.2": os codigos da nota do grupo, com a descricao completa, numa chamada so pela posicao' do
      pela_posicao = fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      dados = buscar('0901.2')['dados']

      expect(dados).to eq(
        'busca' => '0901.2', 'total' => 2,
        'itens' => [{ 'codigo' => '0901.21.00', 'descricao' => "#{cafe}, café torrado, não descafeinado", 'vigente_desde' => '2022-04-01' },
                    { 'codigo' => '0901.22.00', 'descricao' => "#{cafe}, café torrado, descafeinado", 'vigente_desde' => '2022-04-01' }]
      )
      expect(pela_posicao).to have_been_made.once
      expect(buscas_feitas).to eq(['0901'])
    end

    it 'a posicao inteira ("0901"): todos os codigos da nota dela' do
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      dados = buscar('0901')['dados']

      expect(dados['itens']).to include(
        { 'codigo' => '0901.12.00', 'descricao' => "#{cafe}, café não torrado, descafeinado", 'vigente_desde' => '2022-04-01' },
        { 'codigo' => '0901.90.00', 'descricao' => "#{cafe}, outros", 'vigente_desde' => '2022-04-01' }
      )
      expect(dados['itens'].pluck('codigo')).to all(satisfy { |codigo| ncm.digitos(codigo).length == 8 })
      expect(dados['total']).to eq(6)
    end

    # Revisão do #2917 (1): o texto vai ao modelo com teto (`Resposta::MAX_TEXTO`, 160) e o corte comia o texto do
    # próprio código: "brinquedos" voltava 20 códigos com 3 descrições. O texto próprio cabe sempre inteiro.
    it '"9503.00" real: cada codigo com a sua descricao, inteira no fim, dentro do teto' do
      fonte_responde("#{api}?search=9503", fixture('ncm_busca_9503.json'))
      proprios = real('ncm_busca_9503.json').to_h { |dado| [dado['codigo'], ncm::Descricao.limpa(ncm.texto(dado['descricao'])).downcase] }

      da_nota = buscar('9503.00')['dados']['itens']

      expect(da_nota.size).to eq(15)
      expect(da_nota.pluck('descricao').uniq.size).to eq(da_nota.size)
      expect(da_nota.pluck('descricao').map(&:length)).to all(be <= Autonomia::FerramentasProntas::Resposta::MAX_TEXTO)
      expect(da_nota).to all(satisfy { |item| item['descricao'].downcase.end_with?(proprios.fetch(item['codigo'])) })
    end

    it '"brinquedos" real e depois o grupo 9503.00.3: as duas chamadas que o modelo faz' do
      fonte_responde("#{api}?search=brinquedos", fixture('ncm_busca_brinquedos.json'))
      fonte_responde("#{api}?search=9503", fixture('ncm_busca_9503.json'))

      pela_palavra = buscar('brinquedos')['dados']
      expect(pela_palavra['itens'].select { |item| grupo?(item) }.pluck('codigo')).to contain_exactly('9503.00', '9503.00.3')
      expect(pela_palavra['observacao']).to eq(format(ncm::BUSQUE_O_GRUPO, grupo: pela_palavra['itens'].find { |item| grupo?(item) }['codigo']))
      expect(buscar('9503.00.3')['dados']['itens'].pluck('codigo')).to eq(%w[9503.00.31 9503.00.39])
      expect(buscas_feitas).to eq(%w[brinquedos 9503])
    end

    # Revisão do #2917 (A): o grupo com mais de MAX_ITENS códigos da nota cortava pela ordem do código: "3004" (153
    # códigos) mostrava só os 3004.10.xx. Vêm os filhos diretos do grupo, com a orientação para o modelo estreitar.
    it '"3004" real, grupo grande: os filhos diretos, com a descricao completa e a orientacao para estreitar' do
      pela_posicao = fonte_responde("#{api}?search=3004", fixture('ncm_busca_3004.json'))

      dados = buscar('3004')['dados']

      expect(dados['itens'].pluck('codigo')).to eq(%w[3004.10 3004.20 3004.3 3004.4 3004.50 3004.60.00 3004.90])
      expect(dados['total']).to eq(7)
      expect(dados['observacao']).to eq(format(ncm::BUSQUE_O_GRUPO, grupo: '3004.10'))
      expect(dados['itens'].pluck('descricao')).to all(start_with('Medicamentos'))
      expect(dados['itens'].pluck('descricao').map(&:length)).to all(be <= Autonomia::FerramentasProntas::Resposta::MAX_TEXTO)
      expect(pela_posicao).to have_been_made.once
    end

    it 'grupo que nao existe: nao encontrado' do
      fonte_responde("#{api}?search=0901", fixture('ncm_busca_0901.json'))

      expect(buscar('0901.5')['situacao']).to eq('nao_encontrado')
    end

    # Revisão do #2917 (5 e BAIXO): cada item passa uma vez só pelo Nokogiri, e o item fora do formato fica de lado.
    it 'cada item e lido uma vez so, e o item sem descricao valida nao derruba a busca' do
      allow(Nokogiri::HTML5).to receive(:fragment).and_call_original
      fonte_responde("#{api}?search=0901", real('ncm_busca_0901.json') + [{ 'codigo' => '0901.23.00', 'descricao' => '<br>' }])

      dados = buscar('0901.2')['dados']

      expect(dados['itens'].pluck('codigo')).to eq(%w[0901.21.00 0901.22.00])
      expect(Nokogiri::HTML5).to have_received(:fragment).exactly(real('ncm_busca_0901.json').size + 1).times
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

    # Revisão do #2917 (testador): o 7616.10.00 tem 200 letras de texto próprio, e a posição (76.16, "Outras obras de
    # alumínio") saía para caber: o corte de 160 deixava o modelo sem o material. O material vem primeiro.
    it '7616.10.00 real, texto proprio longo: o material vem primeiro e chega ao modelo' do
      fonte_responde("#{api}?search=7616", fixture('ncm_busca_7616.json'))

      descricao = codigo('7616.10.00')['dados']['descricao']

      expect(descricao).to start_with('Outras obras de alumínio, tachas, pregos')
      expect(descricao.length).to be <= Autonomia::FerramentasProntas::Resposta::MAX_TEXTO + 1
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
      expect(a_request(:get, "#{api}/0901")).to have_been_made.once
      expect(a_request(:get, "#{api}/09")).to have_been_made.once
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
