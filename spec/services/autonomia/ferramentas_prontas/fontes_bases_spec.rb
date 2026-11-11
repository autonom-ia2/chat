require 'rails_helper'

# #2858 (F5): as cinco ferramentas das bases baixadas, pelo caminho real (a `Execucao` da pronta de um agente). A base é
# importada dos arquivos fictícios (`FerramentasProntasBasesHelper`, WebMock) e a consulta é no banco, sem rede.
# Também: a busca responde em até 1 s com a base no tamanho real, e nenhuma pessoa física chega ao modelo.
RSpec.describe Autonomia::FerramentasProntas::Fontes do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:bases) { Autonomia::FerramentasProntas::Bases }
  let(:flag) { Autonomia::FerramentasProntas::Bases::FLAG }

  before do
    resolver_hosts_das_prontas
    bases.importadores.each { |importador| stub_const("#{importador.name}::MINIMO", 1) }
    account.enable_features!(Autonomia::FerramentasProntas::FLAG, flag)
  end

  around { |example| travel_to(Time.zone.parse('2026-11-11 12:00 UTC')) { example.run } }

  def nao_consegui?(saida)
    saida['situacao'] == 'nao_consegui_consultar' && !saida.key?('dados')
  end

  it 'sem a flag das bases, as cinco não entram na vitrine nem no turno' do
    account.disable_features!(flag)

    %w[planos_de_saude aeronaves geracao_solar transportadoras queimadas].each do |chave|
      expect { incluir_pronta(chave, conta: account, agente: agent) }
        .to raise_error(Autonomia::FerramentasProntas::Incluir::Recusado, 'desligada')
    end
    expect(Autonomia::FerramentasProntas.disponiveis(account).map(&:chave)).not_to include('aeronaves')
  end

  it 'base que nunca foi baixada: "não consegui", nunca "não tem"' do
    ferramenta = incluir_pronta('aeronaves', conta: account, agente: agent)

    saida = executar_pronta(ferramenta, 'matricula' => 'PR-XYZ')

    expect(nao_consegui?(saida)).to be(true)
    expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('rab.base_vazia' => 1)
  end

  it 'a pronta da base responde na hora (sem host: não vai para a consulta em segundo plano)' do
    ferramenta = incluir_pronta('transportadoras', conta: account, agente: agent)

    expect(Autonomia::FerramentasProntas.calculada_aqui?(ferramenta)).to be(true)
  end

  describe 'Planos de saúde' do
    let(:ferramenta) { incluir_pronta('planos_de_saude', conta: account, agente: agent) }

    before do
      arquivo_responde('https://dadosabertos.ans.gov.br/FTP/PDA/operadoras_de_plano_de_saude_ativas/Relatorio_cadop.csv', ans_ativas)
      arquivo_responde('https://dadosabertos.ans.gov.br/FTP/PDA/operadoras_de_plano_de_saude_canceladas/Relatorio_cadop_canceladas.csv',
                       ans_canceladas)
      importar('planos_de_saude')
    end

    it '"A operadora do CNPJ X está ativa?": a situação, a modalidade, a cidade e de quando é a base' do
      saida = executar_pronta(ferramenta, 'cnpj' => '11.222.333/0001-81')

      expect(saida['situacao']).to eq('encontrado')
      expect(saida['dados']).to include('total' => 1, 'atualizado_em' => '2026-11-11')
      expect(saida['dados']['operadoras']).to eq([{ 'razao_social' => 'SAÚDE EXEMPLO 1 LTDA', 'nome_fantasia' => 'PLANO EXEMPLO 1',
                                                    'registro_ans' => '300001', 'cnpj' => '11222333000181', 'situacao' => 'ativa',
                                                    'modalidade' => 'Medicina de Grupo', 'cidade' => 'Campinas', 'uf' => 'SP',
                                                    'registrada_em' => '2015-05-19' }])
    end

    it 'a cancelada diz quando e por quê; a busca pelo nome ignora acento e caixa' do
      saida = executar_pronta(ferramenta, 'nome' => 'odonto exemplo')

      expect(saida['dados']['operadoras'].sole).to include('situacao' => 'cancelada', 'cancelada_em' => '2026-11-05',
                                                           'motivo_do_cancelamento' => 'INEXISTÊNCIA DE PRODUTO ATIVO POR MAIS DE 180 DIAS')
      expect(executar_pronta(ferramenta, 'nome' => 'saude exemplo')['dados']).to include('total' => 3)
    end

    it 'pelo registro na ANS; sem nenhum dos três, nada é consultado' do
      expect(executar_pronta(ferramenta, 'registro_ans' => '300002')['dados']['operadoras'].sole['registro_ans']).to eq('300002')
      expect(executar_pronta(ferramenta, {})).to include('situacao' => 'pedido_invalido', 'campo' => 'nome')
      expect(executar_pronta(ferramenta, 'registro_ans' => '999999')['situacao']).to eq('nao_encontrado')
    end
  end

  describe 'Aeronaves' do
    let(:ferramenta) { incluir_pronta('aeronaves', conta: account, agente: agent) }

    before do
      arquivo_responde('https://sistemas.anac.gov.br/dadosabertos/Aeronaves/RAB/dados_aeronaves.csv', rab)
      importar('aeronaves')
    end

    it '"Matrícula PR-XYZ?": modelo, situação, certificado, gravames e a empresa dona; o operador pessoa física não aparece' do
      saida = executar_pronta(ferramenta, 'matricula' => 'pr-xyz')

      aeronave = saida['dados']['aeronaves'].sole
      expect(aeronave).to include('matricula' => 'PRXYZ', 'modelo' => 'R66', 'situacao' => 'registrada',
                                  'certificado_de_aeronavegabilidade_valido_ate' => '2027-11-03', 'outros_operadores' => 1)
      expect(aeronave['proprietarios_empresas'].sole).to include('nome' => 'AVIACAO EXEMPLO S.A')
      expect(saida.to_json).not_to include('FULANO', FerramentasProntasBasesHelper::CPF_PESSOA)
    end

    it 'a de pessoa física responde a aeronave, sem dono nenhum' do
      saida = executar_pronta(ferramenta, 'matricula' => 'PTABC')

      expect(saida['dados']['aeronaves'].sole).to include('outros_proprietarios' => 1)
      expect(saida.to_json).not_to include('FULANO', FerramentasProntasBasesHelper::CPF_PESSOA, '"MT"')
    end

    it 'matrícula fora do padrão é pedido inválido, sem consultar' do
      expect(executar_pronta(ferramenta, 'matricula' => 'N12345')).to include('situacao' => 'pedido_invalido', 'campo' => 'matricula')
    end
  end

  describe 'Placas solares' do
    let(:ferramenta) { incluir_pronta('geracao_solar', conta: account, agente: agent) }

    before do
      arquivo_responde(Autonomia::FerramentasProntas::Bases::GeracaoSolar::ARQUIVO, gd_zip)
      importar('geracao_solar')
    end

    it '"Tem geração solar no CEP X?": quantos sistemas, a potência, por tipo e por classe' do
      saida = executar_pronta(ferramenta, 'consulta' => 'cep', 'cep' => '78890-000')

      expect(saida['dados']).to include('cep' => '78890000', 'sistemas' => 3, 'potencia_kw' => 85.0,
                                        'por_tipo' => { 'solar' => 3 }, 'por_classe' => { 'Residencial' => 2, 'Rural' => 1 },
                                        'atualizado_em' => '2026-11-11')
    end

    it 'na cidade inteira, pelo nome e UF (Sorriso, MT)' do
      saida = executar_pronta(ferramenta, 'consulta' => 'cidade', 'cidade' => 'sorriso', 'uf' => 'MT')

      expect(saida['dados']).to include('cidade' => 'Sorriso', 'uf' => 'MT', 'sistemas' => 4, 'por_tipo' => { 'solar' => 3, 'eólica' => 1 })
    end

    it 'CEP sem nenhum sistema: não encontrado' do
      expect(executar_pronta(ferramenta, 'consulta' => 'cep', 'cep' => '01001000')['situacao']).to eq('nao_encontrado')
    end
  end

  describe 'Transportadoras' do
    let(:ferramenta) { incluir_pronta('transportadoras', conta: account, agente: agent) }

    before do
      arquivo_responde('https://dados.antt.gov.br/api/3/action/package_show?id=rntrc', antt_catalogo, tipo: 'application/json')
      arquivo_responde(FerramentasProntasBasesHelper::ANTT_CSV, antt)
      importar('transportadoras')
    end

    it '"O RNTRC da transportadora CNPJ X está ativo?": situação, categoria, município e datas' do
      saida = executar_pronta(ferramenta, 'cnpj' => '11.222.333/0001-81')

      expect(saida['dados']['registros']).to eq([{ 'rntrc' => '050085788', 'situacao' => 'ativo', 'categoria' => 'empresa',
                                                   'nome' => 'TRANSPORTES EXEMPLO LTDA', 'cnpj' => '11222333000181',
                                                   'municipio' => 'RIBEIRÃO PRETO', 'uf' => 'SP', 'cadastrado_em' => '2017-05-23',
                                                   'situacao_desde' => '2026-08-27', 'equiparado' => true }])
    end

    it 'pelo número do RNTRC, com ou sem o zero da frente; do autônomo, nem nome nem CPF' do
      saida = executar_pronta(ferramenta, 'rntrc' => '44031531')

      expect(saida['dados']['registros'].sole).to include('rntrc' => '044031531', 'situacao' => 'ativo', 'categoria' => 'autônomo')
      expect(saida['dados']['registros'].sole.keys).not_to include('nome', 'cnpj')
      expect(saida.to_json).not_to include('FULANO')
    end

    it 'sem registro na base: não encontrado (a ANTT só publica ativos e pendentes)' do
      expect(executar_pronta(ferramenta, 'rntrc' => '000000001')['situacao']).to eq('nao_encontrado')
      expect(executar_pronta(ferramenta, 'rntrc' => '12345678901')).to include('situacao' => 'pedido_invalido')
    end
  end

  describe 'Focos de queimada' do
    let(:ferramenta) { incluir_pronta('queimadas', conta: account, agente: agent) }

    before do
      (0...8).each do |atras|
        dia = (Date.new(2026, 11, 11) - atras).iso8601
        focos = [['13:40:00', '-12.5450', '-55.7110', '5107925'], ['14:00:00', '-12.9000', '-55.7110', '5107925'],
                 ['15:00:00', '-3.1', '-60.0', '1302603']]
        arquivo_responde(inpe_url(dia), inpe_dia(dia, focos))
      end
      importar('queimadas')
    end

    it '"Queimada em Sorriso ontem?": os do município, por dia, no fuso da conta' do
      saida = executar_pronta(ferramenta, 'cidade' => 'Sorriso', 'uf' => 'MT', 'dias' => 1)

      expect(saida['dados']).to include('onde' => 'Sorriso (MT)', 'desde' => '2026-11-10', 'total' => 4,
                                        'por_dia' => { '2026-11-11' => 2, '2026-11-10' => 2 })
      expect(saida['dados']['mais_recentes'].first).to include('quando' => '2026-11-11 11:00', 'bioma' => 'Amazônia')
    end

    it 'num raio em volta da sede, com a distância; o foco mais longe que o raio fica de fora' do
      saida = executar_pronta(ferramenta, 'cidade' => 'Sorriso', 'uf' => 'MT', 'raio_km' => 20, 'dias' => 7)

      expect(saida['dados']).to include('onde' => 'até 20 km de Sorriso (MT)', 'total' => 8)
      expect(saida['dados']['mais_recentes'].first['distancia_km']).to be < 20
    end

    it 'pela localização que o cliente mandou, 10 km por padrão' do
      saida = executar_pronta(ferramenta, 'latitude' => -3.1, 'longitude' => -60.0)

      expect(saida['dados']).to include('onde' => 'até 10 km de a localização informada', 'total' => 2)
    end

    it 'sem cidade nem localização: pedido inválido' do
      expect(executar_pronta(ferramenta, 'dias' => 2)).to include('situacao' => 'pedido_invalido', 'campo' => 'cidade')
    end

    it 'nenhum foco no lugar: total zero, com a data da base (o agente diz "nenhum foco até tal dia")' do
      saida = executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'SP')

      expect(saida['situacao']).to eq('encontrado')
      expect(saida['dados']).to include('onde' => 'Campinas (SP)', 'total' => 0, 'atualizado_em' => '2026-11-11', 'mais_recentes' => [])
    end

    it 'base de focos com mais de 1 dia: "não consegui", nunca "nenhum foco"' do
      travel 2.days

      saida = executar_pronta(ferramenta, 'cidade' => 'Campinas', 'uf' => 'SP')

      expect(nao_consegui?(saida)).to be(true)
      expect(Autonomia::FerramentasProntas::Uso.last.motivos).to eq('inpe.base_desatualizada' => 1)
    end
  end

  describe 'a busca responde em até 1 s com a base no tamanho real' do
    def gerar(sql)
      ActiveRecord::Base.connection.execute(sql)
    end

    def em_ate_um_segundo
      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      saida = yield
      [saida, Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio]
    end

    before do
      %w[transportadoras geracao_solar queimadas aeronaves planos_de_saude].each do |base|
        bases::Estado.create!(base: base, geracao_ativa: 1, atualizado_em: Time.current, linhas: 1)
      end
      gerar(<<~SQL.squish)
        INSERT INTO autonomia_prontas_transportadores (geracao, rntrc, cnpj, nome, categoria, situacao)
        SELECT g, lpad(n::text, 9, '0'), CASE WHEN n = 543210 THEN '11222333000181' WHEN n % 3 = 0 THEN lpad(n::text, 14, '0') END, 'EMPRESA ' || n, 'empresa', 'ativo'
        FROM generate_series(1, 2) g, generate_series(1, 600000) n
      SQL
      gerar(<<~SQL.squish)
        INSERT INTO autonomia_prontas_geracao_distribuida (geracao, cep, codigo_municipio, uf, tipo, classe, quantidade, potencia_kw)
        SELECT g, lpad((10000000 + n)::text, 8, '0'), CASE WHEN n % 600 = 0 THEN '3509502' ELSE (3500000 + n % 600)::text END, 'SP', 'solar', 'Residencial', 3, 9.5
        FROM generate_series(1, 2) g, generate_series(1, 220000) n
      SQL
      gerar(<<~SQL.squish)
        INSERT INTO autonomia_prontas_focos_queimada (geracao, detectado_em, latitude, longitude, codigo_municipio)
        SELECT 1, now() - (n % 150 || ' hours')::interval, -20 + (n % 1000) * 0.02, -60 + (n % 997) * 0.02, (5100000 + n % 140)::text
        FROM generate_series(1, 70000) n
      SQL
      gerar('ANALYZE autonomia_prontas_transportadores, autonomia_prontas_geracao_distribuida, autonomia_prontas_focos_queimada')
    end

    it 'transportadora pelo RNTRC e pelo CNPJ, placas solares no CEP e na cidade, focos no raio' do
      transportadoras = incluir_pronta('transportadoras', conta: account, agente: agent)
      solar = incluir_pronta('geracao_solar', conta: account, agente: agent)
      queimadas = incluir_pronta('queimadas', conta: account, agente: agent)
      consultas = [
        [transportadoras, { 'rntrc' => '000543210' }], [transportadoras, { 'cnpj' => '11222333000181' }],
        [solar, { 'consulta' => 'cep', 'cep' => '10123456' }], [solar, { 'consulta' => 'cidade', 'cidade' => 'Campinas', 'uf' => 'SP' }],
        [queimadas, { 'latitude' => -15.0, 'longitude' => -55.0, 'raio_km' => 50, 'dias' => 7 }]
      ]

      consultas.each do |ferramenta, argumentos|
        saida, segundos = em_ate_um_segundo { executar_pronta(ferramenta, argumentos) }
        expect(saida['situacao']).to eq('encontrado')
        expect(segundos).to be < 1.0
      end
    end

    it 'a busca usa o índice (não varre a tabela)' do
      plano = ActiveRecord::Base.connection.select_values(
        "EXPLAIN #{bases::Transportador.where(geracao: 1, rntrc: '000543210').to_sql}"
      ).join("\n")

      expect(plano).to include('idx_prontas_transportadores_rntrc')
      expect(plano).not_to include('Seq Scan on autonomia_prontas_transportadores')
    end
  end

  describe 'a troca da geração no meio da busca (entre um comando e outro)' do
    # Na primeira consulta SQL que tem `trecho` (ou todos os trechos da lista), a importação troca a geração e apaga a
    # antiga, como na vida real.
    def trocar_no(trecho, base:, modelo:, &)
      trocou = false
      troca = lambda do |*, payload|
        next if trocou || !Array(trecho).all? { |parte| payload[:sql].to_s.include?(parte) }

        trocou = true
        bases::Estado.find_by!(base: base).update!(geracao_ativa: 2)
        modelo.where(geracao: 1).delete_all
      end
      saida = ActiveSupport::Notifications.subscribed(troca, 'sql.active_record', &)
      [saida, trocou]
    end

    it 'placas solares: a soma, o tipo e a classe vêm todos da mesma geração' do
      bases::Estado.create!(base: 'geracao_solar', geracao_ativa: 1, atualizado_em: Time.current, linhas: 1)
      gd = bases::GeracaoDistribuida
      local = { cep: '78890000', codigo_municipio: '5107925', uf: 'MT' }
      gd.create!(local.merge(geracao: 1, tipo: 'solar', classe: 'Residencial', quantidade: 2, potencia_kw: 10))
      gd.create!(local.merge(geracao: 2, tipo: 'solar', classe: 'Residencial', quantidade: 5, potencia_kw: 50))
      gd.create!(local.merge(geracao: 2, tipo: 'eólica', classe: 'Comercial', quantidade: 4, potencia_kw: 40))
      ferramenta = incluir_pronta('geracao_solar', conta: account, agente: agent)

      saida, trocou = trocar_no('SUM(', base: 'geracao_solar', modelo: gd) do
        executar_pronta(ferramenta, 'consulta' => 'cep', 'cep' => '78890000')
      end

      expect(trocou).to be(true)
      expect(saida['dados']).to include('sistemas' => 9, 'potencia_kw' => 90.0, 'por_tipo' => { 'solar' => 5, 'eólica' => 4 },
                                        'por_classe' => { 'Residencial' => 5, 'Comercial' => 4 })
    end

    it 'planos de saúde: a lista e a contagem (quando passa de 10) vêm da mesma geração' do
      bases::Estado.create!(base: 'planos_de_saude', geracao_ativa: 1, atualizado_em: Time.current, linhas: 1)
      { 1 => ['UM', 12], 2 => ['DOIS', 15] }.each do |geracao, (nome, quantas)|
        (1..quantas).each do |n|
          bases::Operadora.create!(geracao: geracao, registro_ans: format('%<g>d%<n>05d', g: geracao, n: n), razao_social: "#{nome} #{n}",
                                   nome_busca: "saude #{nome.downcase} #{n}", ativa: true)
        end
      end
      ferramenta = incluir_pronta('planos_de_saude', conta: account, agente: agent)

      saida, trocou = trocar_no(%w[autonomia_prontas_operadoras_ans LIMIT], base: 'planos_de_saude', modelo: bases::Operadora) do
        executar_pronta(ferramenta, 'nome' => 'saude')
      end

      expect(trocou).to be(true)
      expect(saida['dados']).to include('total' => 15, 'mostrando' => 10)
      expect(saida['dados']['operadoras'].pluck('razao_social')).to all(start_with('DOIS'))
    end
  end
end
