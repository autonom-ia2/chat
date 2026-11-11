require 'rails_helper'

# #2858 (F5): a importação das bases baixadas. O aceite da fase, base a base:
#   - a primeira importação fica completa (todas as linhas, sem pessoa física);
#   - a segunda rodada atualiza sem duplicar (geração nova, a antiga apagada);
#   - numa falha simulada (fonte fora, formato mudado, arquivo cortado), os dados ficam e o alerta chega (log e Sentry).
# Os arquivos são fictícios e vêm do WebMock (`FerramentasProntasBasesHelper`); nenhum pedido sai para a rede.
RSpec.describe Autonomia::FerramentasProntas::Bases::Importacao do
  let(:bases) { Autonomia::FerramentasProntas::Bases }
  let(:estado) { ->(chave) { bases::Estado.find_by(base: chave) } }

  before do
    resolver_hosts_das_prontas
    bases.importadores.each { |importador| stub_const("#{importador.name}::MINIMO", 1) }
  end

  around do |example|
    travel_to(Time.zone.parse('2026-11-11 10:47 UTC')) do
      example.run
    end
  end

  describe 'Planos de saúde (ANS)' do
    let(:ativas) { 'https://dadosabertos.ans.gov.br/FTP/PDA/operadoras_de_plano_de_saude_ativas/Relatorio_cadop.csv' }
    let(:canceladas) { 'https://dadosabertos.ans.gov.br/FTP/PDA/operadoras_de_plano_de_saude_canceladas/Relatorio_cadop_canceladas.csv' }
    let(:operadoras) { bases::Operadora.vigente }

    before do
      arquivo_responde(ativas, ans_ativas)
      arquivo_responde(canceladas, ans_canceladas)
    end

    it 'a primeira importação fica completa: ativas e canceladas, sem representante, e-mail nem telefone' do
      expect(importar('planos_de_saude')).to eq(:atualizada)

      expect(operadoras.count).to eq(4)
      primeira = operadoras.find_by(registro_ans: '300001')
      expect(primeira.attributes).to include('cnpj' => FerramentasProntasBasesHelper::CNPJ_EMPRESA, 'razao_social' => 'SAÚDE EXEMPLO 1 LTDA',
                                             'modalidade' => 'Medicina de Grupo', 'cidade' => 'Campinas', 'uf' => 'SP', 'ativa' => true)
      cancelada = operadoras.find_by(registro_ans: '400001')
      expect(cancelada.attributes).to include('ativa' => false, 'cancelada_em' => Date.new(2026, 11, 5),
                                              'motivo_do_cancelamento' => 'INEXISTÊNCIA DE PRODUTO ATIVO POR MAIS DE 180 DIAS')
      gravado = bases::Operadora.pluck(Arel.sql('row_to_json(autonomia_prontas_operadoras_ans)::text')).join
      expect(gravado).not_to include('FULANO', 'BELTRANA', 'exemplo.test', '30000000')
      expect(estado.call('planos_de_saude')).to have_attributes(geracao_ativa: 1, linhas: 4, atualizado_em: Time.current, falhou_em: nil)
    end

    it 'a segunda rodada atualiza sem duplicar: a geração antiga sai depois da troca' do
      importar('planos_de_saude')
      arquivo_responde(ativas, ans_ativas(5))

      travel 1.day
      expect(importar('planos_de_saude')).to eq(:atualizada)

      expect(bases::Operadora.count).to eq(6)
      expect(bases::Operadora.distinct.pluck(:geracao)).to eq([2])
      expect(bases::Operadora.vigente.where(registro_ans: '300001').count).to eq(1)
      expect(estado.call('planos_de_saude')).to have_attributes(geracao_ativa: 2, linhas: 6)
    end

    it 'fonte fora do ar: a cópia anterior continua valendo e o alerta vai ao Sentry e ao log, nunca ao Guia' do
      importar('planos_de_saude')
      stub_request(:get, canceladas).to_return(status: 503, body: 'fora')
      allow(Rails.logger).to receive(:warn).and_call_original
      sentry = stub_const('Sentry', Class.new { def self.capture_message(*, **) = nil })
      allow(sentry).to receive(:capture_message)

      travel 1.day
      resultado = with_modified_env(SENTRY_DSN: 'https://chave@sentry.exemplo.test/1') { importar('planos_de_saude') }

      expect(resultado).to eq(:falhou)
      expect(operadoras.count).to eq(4)
      expect(bases::Operadora.distinct.pluck(:geracao)).to eq([1])
      expect(estado.call('planos_de_saude')).to have_attributes(geracao_ativa: 1, motivo_da_falha: 'erro_da_fonte', atualizado_em: 1.day.ago)
      expect(sentry).to have_received(:capture_message).with(include('planos_de_saude: erro_da_fonte'), hash_including(level: :warning))
      expect(Rails.logger).to have_received(:warn).with(include('ALERTA base=planos_de_saude motivo=erro_da_fonte vale_a_copia_de=2026-11-11'))
      expect(Autonomia::Guide::Aviso.count).to eq(0)
    end

    it 'o formato mudou (coluna sumiu): nada troca e o alerta diz formato_mudou' do
      importar('planos_de_saude')
      arquivo_responde(ativas, ans_ativas.sub('RAZAO_SOCIAL', 'NOME'))

      travel 1.day
      expect(importar('planos_de_saude')).to eq(:falhou)

      expect(operadoras.count).to eq(4)
      expect(estado.call('planos_de_saude').motivo_da_falha).to eq('formato_mudou')
    end

    it 'o arquivo veio cortado (menos da metade das linhas): recusado, a cópia anterior fica' do
      arquivo_responde(ativas, ans_ativas(9))
      importar('planos_de_saude')
      arquivo_responde(ativas, ans_ativas(2))

      travel 1.day
      expect(importar('planos_de_saude')).to eq(:falhou)

      expect(operadoras.count).to eq(10)
      expect(estado.call('planos_de_saude').motivo_da_falha).to eq('base_encolheu')
    end

    it 'sem Sentry configurado, o alerta fica só no log, sem quebrar' do
      stub_request(:get, ativas).to_timeout
      allow(Rails.logger).to receive(:warn).and_call_original
      sentry = stub_const('Sentry', Class.new { def self.capture_message(*, **) = nil })
      allow(sentry).to receive(:capture_message)

      expect(with_modified_env(SENTRY_DSN: nil) { importar('planos_de_saude') }).to eq(:falhou)

      expect(sentry).not_to have_received(:capture_message)
      expect(Rails.logger).to have_received(:warn).with(include('ALERTA base=planos_de_saude motivo=falha_de_rede vale_a_copia_de=nunca'))
    end

    it 'o defeito nosso vai ao rastreador de erros antes do alerta, e a cópia que vale fica' do
      importar('planos_de_saude')
      allow(bases::PlanosDeSaude).to receive(:linhas).and_raise(NoMethodError, 'defeito')
      ordem = []
      allow(ChatwootExceptionTracker).to(receive(:new).and_wrap_original do |original, *args|
        ordem << :rastreador
        original.call(*args)
      end)
      allow(bases::Alerta).to(receive(:falhou!).and_wrap_original do |original, *args|
        ordem << :alerta
        original.call(*args)
      end)

      travel 1.day
      expect(importar('planos_de_saude')).to eq(:falhou)

      expect(ordem).to eq(%i[rastreador alerta])
      expect(estado.call('planos_de_saude')).to have_attributes(geracao_ativa: 1, motivo_da_falha: 'defeito')
      expect(operadoras.count).to eq(4)
    end

    it 'a falha DEPOIS da troca (apagar a antiga) não apaga a geração nova: ela vale, e a próxima rodada termina a limpeza' do
      importar('planos_de_saude')
      arquivo_responde(ativas, ans_ativas(5))
      allow(bases::Alerta).to receive(:falhou!)
      allow_any_instance_of(described_class).to receive(:apagar_antigas).and_raise(ActiveRecord::StatementInvalid, 'caiu') # rubocop:disable RSpec/AnyInstance

      travel 1.day
      expect(importar('planos_de_saude')).to eq(:atualizada)

      expect(estado.call('planos_de_saude')).to have_attributes(geracao_ativa: 2, linhas: 6, atualizado_em: Time.current,
                                                                motivo_da_falha: 'limpeza_pendente')
      expect(bases::Operadora.group(:geracao).count).to eq(1 => 4, 2 => 6)
      expect(bases::Alerta).to have_received(:falhou!).with('planos_de_saude', 'limpeza_pendente', anything)

      allow_any_instance_of(described_class).to receive(:apagar_antigas).and_call_original # rubocop:disable RSpec/AnyInstance
      travel 1.day
      expect(importar('planos_de_saude')).to eq(:atualizada)
      expect(bases::Operadora.distinct.pluck(:geracao)).to eq([3])
      expect(estado.call('planos_de_saude').motivo_da_falha).to be_nil
    end

    it 'o COPY de uma base grande não cai no statement_timeout do banco (o teto da busca não vale para ele)' do
      ActiveRecord::Base.connection.execute("SET statement_timeout = '300ms'")
      lento = Enumerator.new do |saida|
        4.times do |n|
          sleep 0.15
          saida << [format('9%05d', n), nil, "LENTA #{n}", nil, 'lenta', nil, nil, nil, nil, true, nil, nil]
        end
      end
      allow(bases::PlanosDeSaude).to receive(:linhas).and_return(lento)

      expect(importar('planos_de_saude')).to eq(:atualizada)

      expect(operadoras.count).to eq(4)
      expect(ActiveRecord::Base.connection.select_value('SHOW statement_timeout')).to eq('300ms')
    ensure
      ActiveRecord::Base.connection.execute('SET statement_timeout = 0')
    end

    it 'outra rodada da mesma base em andamento: não faz nada' do
      Redis::Alfred.set('autonomia:prontas:base:planos_de_saude', 'outra', nx: true, ex: 60)

      expect(importar('planos_de_saude')).to eq(:ocupada)
      expect(a_request(:get, ativas)).not_to have_been_made
    ensure
      Redis::Alfred.delete('autonomia:prontas:base:planos_de_saude')
    end

    it 'outra máquina já importa a base (trava no banco, além da do Redis): não faz nada' do
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      outra = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username], password: config[:password])
      outra.exec("SELECT pg_advisory_lock(#{described_class.trava_no_banco('planos_de_saude')})")

      expect(importar('planos_de_saude')).to eq(:ocupada)
      expect(a_request(:get, ativas)).not_to have_been_made
      expect(Redis::Alfred.get('autonomia:prontas:base:planos_de_saude')).to be_nil
    ensure
      outra&.close
    end

    it 'um campo gigante no CSV (mais de 64 KB) é formato mudado, sem ler o resto' do
      arquivo_responde(ativas, ans_ativas.sub('SAÚDE EXEMPLO 1 LTDA', 'X' * 70_000))

      expect(importar('planos_de_saude')).to eq(:falhou)
      expect(estado.call('planos_de_saude').motivo_da_falha).to eq('formato_mudou')
    end

    it 'a trava do Redis sai mesmo quando soltar a do banco quebra' do
      allow_any_instance_of(described_class).to receive(:destravar_no_banco).and_raise(PG::ConnectionBad, 'caiu') # rubocop:disable RSpec/AnyInstance

      expect { importar('planos_de_saude') }.to raise_error(PG::ConnectionBad)

      expect(Redis::Alfred.get('autonomia:prontas:base:planos_de_saude')).to be_nil
    ensure
      ActiveRecord::Base.connection.select_value('SELECT pg_advisory_unlock_all()')
    end

    it 'apagar a geração antiga também roda com o teto longo, lote a lote (não cai no statement_timeout da busca)' do
      importar('planos_de_saude')
      comandos = []
      guardar = ->(*, payload) { comandos << payload[:sql].to_s }

      travel 1.day
      ActiveSupport::Notifications.subscribed(guardar, 'sql.active_record') { importar('planos_de_saude') }

      apagar = comandos.each_index.select { |i| comandos[i].start_with?('DELETE FROM "autonomia_prontas_operadoras_ans"') }
      expect(apagar).not_to be_empty
      expect(apagar).to all(satisfy { |i| comandos[0...i].reverse.find { |sql| sql.include?('statement_timeout') }.include?("'2h'") })
    end

    it 'a sobra de uma rodada que morreu no meio é apagada antes da próxima' do
      importar('planos_de_saude')
      bases::Operadora.create!(geracao: 7, registro_ans: '999999', ativa: true)

      travel 1.day
      importar('planos_de_saude')

      expect(bases::Operadora.where(registro_ans: '999999')).to be_empty
    end
  end

  describe 'Aeronaves (RAB da ANAC)' do
    let(:url) { 'https://sistemas.anac.gov.br/dadosabertos/Aeronaves/RAB/dados_aeronaves.csv' }

    before { arquivo_responde(url, rab, tipo: 'application/octet-stream') }

    it 'pula a linha antes do cabeçalho, guarda a empresa e NUNCA a pessoa física (nem nome, nem CPF, nem UF)' do
      expect(importar('aeronaves')).to eq(:atualizada)

      expect(bases::Aeronave.vigente.count).to eq(3)
      empresa = bases::Aeronave.vigente.find_by(matricula: 'PRXYZ').dados
      expect(empresa).to include('fabricante' => 'ROBINSON HELICOPTER', 'modelo' => 'R66', 'ano_de_fabricacao' => '2020',
                                 'situacao' => 'registrada', 'certificado_de_aeronavegabilidade_valido_ate' => '2027-11-03',
                                 'gravames' => ['ALIENAÇÃO FIDUCIÁRIA', 'O.J. RESTRITIVA DE TRANSFERÊNCIA'],
                                 'proprietarios_empresas' => [{ 'nome' => 'AVIACAO EXEMPLO S.A', 'cnpj' => '11222333000181', 'uf' => 'SP' }],
                                 'outros_operadores' => 1)
      pessoa = bases::Aeronave.vigente.find_by(matricula: 'PTABC').dados
      expect(pessoa).to include('outros_proprietarios' => 1)
      expect(pessoa).not_to have_key('proprietarios_empresas')
      cancelada = bases::Aeronave.vigente.find_by(matricula: 'PPCAN').dados
      expect(cancelada).to include('situacao' => 'cancelada', 'cancelada_em' => '2010-02-01', 'motivo_do_cancelamento' => 'PERECIMENTO')
      gravado = bases::Aeronave.pluck(:dados).to_json
      expect(gravado).not_to include('FULANO', FerramentasProntasBasesHelper::CPF_PESSOA, 'MT')
    end

    it 'o nome da empresa sai sem o CPF que o MEI leva no nome; documento que é CPF não grava nome' do
      mei = [{ 'NOME' => "TAXI AEREO FULANO #{FerramentasProntasBasesHelper::CPF_MEI}", 'DOCUMENTO' => FerramentasProntasBasesHelper::CNPJ_MEI,
               'UF' => 'GO' },
             { 'NOME' => 'CICLANO 987.654.321-00 ME', 'DOCUMENTO' => FerramentasProntasBasesHelper::CNPJ_OUTRA, 'UF' => 'GO' }]
      corpo = "#{rab}\r\n#{rab_linha('PRMEI', proprietarios: mei)}"
      arquivo_responde(url, corpo)

      importar('aeronaves')

      donos = bases::Aeronave.vigente.find_by(matricula: 'PRMEI').dados['proprietarios_empresas']
      expect(donos).to eq([{ 'nome' => 'TAXI AEREO FULANO', 'cnpj' => FerramentasProntasBasesHelper::CNPJ_MEI, 'uf' => 'GO' },
                           { 'nome' => 'CICLANO ME', 'cnpj' => FerramentasProntasBasesHelper::CNPJ_OUTRA, 'uf' => 'GO' }])
      expect(bases::Aeronave.pluck(:dados).to_json).not_to include(FerramentasProntasBasesHelper::CPF_MEI, '987.654.321-00')
    end

    it 'o CPF grudado no nome ("FULANO-98765432100") também sai, pelos últimos 11 dígitos' do
      mei = [{ 'NOME' => "AEROCLUBE FULANO-#{FerramentasProntasBasesHelper::CPF_MEI}", 'DOCUMENTO' => FerramentasProntasBasesHelper::CNPJ_MEI },
             { 'NOME' => 'TAXI 987.654.321-00X', 'DOCUMENTO' => FerramentasProntasBasesHelper::CNPJ_OUTRA },
             { 'NOME' => 'VOO 12345', 'DOCUMENTO' => FerramentasProntasBasesHelper::CNPJ_EMPRESA }]
      arquivo_responde(url, "#{rab}\r\n#{rab_linha('PRGRU', proprietarios: mei)}")

      importar('aeronaves')

      nomes = bases::Aeronave.vigente.find_by(matricula: 'PRGRU').dados['proprietarios_empresas'].pluck('nome')
      expect(nomes).to eq(['AEROCLUBE FULANO', 'TAXI 987.654.321-00X', 'VOO 12345'])
    end

    it 'o JSON de donos quebrado não vira "0 outros": a contagem some (não se sabe)' do
      linha = rab_linha('PRQBR', proprietarios: []).sub('"[]"', '"[{quebrado"')
      arquivo_responde(url, "#{rab}\r\n#{linha}")

      importar('aeronaves')

      dados = bases::Aeronave.vigente.find_by(matricula: 'PRQBR').dados
      expect(dados.keys).not_to include('outros_proprietarios', 'proprietarios_empresas')
      expect(dados).to include('outros_operadores' => 0)
    end

    it 'a segunda rodada não duplica' do
      importar('aeronaves')
      travel 1.day
      importar('aeronaves')

      expect(bases::Aeronave.count).to eq(3)
      expect(estado.call('aeronaves').geracao_ativa).to eq(2)
    end
  end

  describe 'Placas solares (geração distribuída da ANEEL)' do
    let(:url) { Autonomia::FerramentasProntas::Bases::GeracaoSolar::ARQUIVO }

    before { arquivo_responde(url, gd_zip, tipo: 'application/zip') }

    it 'lê o CSV de dentro do ZIP e guarda só a soma por CEP, município, tipo e classe, sem titular' do
      expect(importar('geracao_solar')).to eq(:atualizada)

      linhas = bases::GeracaoDistribuida.vigente.order(:cep, :classe).map do |linha|
        linha.attributes.slice('cep', 'codigo_municipio', 'uf', 'tipo', 'classe', 'quantidade').merge('kw' => linha.potencia_kw.to_f)
      end
      expect(linhas).to eq([
                             { 'cep' => '78890000', 'codigo_municipio' => '5107925', 'uf' => 'MT', 'tipo' => 'solar', 'classe' => 'Residencial',
                               'quantidade' => 2, 'kw' => 10.0 },
                             { 'cep' => '78890000', 'codigo_municipio' => '5107925', 'uf' => 'MT', 'tipo' => 'solar', 'classe' => 'Rural',
                               'quantidade' => 1, 'kw' => 75.0 },
                             { 'cep' => '78891000', 'codigo_municipio' => '5107925', 'uf' => 'MT', 'tipo' => 'eólica', 'classe' => 'Comercial',
                               'quantidade' => 1, 'kw' => 10.0 }
                           ])
      expect(estado.call('geracao_solar').linhas).to eq(3)
    end

    it 'o CSV aberto maior que o teto (bomba de zip): recusado antes de ler' do
      stub_const('Autonomia::FerramentasProntas::Bases::GeracaoSolar::MAX_ABERTO', 100)

      expect(importar('geracao_solar')).to eq(:falhou)
      expect(estado.call('geracao_solar').motivo_da_falha).to eq('arquivo_grande_demais')
    end

    it 'o ZIP anunciado maior que o teto do download: recusado' do
      stub_const('Autonomia::FerramentasProntas::Bases::GeracaoSolar::MAX_BYTES', 100)

      expect(importar('geracao_solar')).to eq(:falhou)
      expect(estado.call('geracao_solar').motivo_da_falha).to eq('arquivo_grande_demais')
    end

    it 'o ZIP que mente o tamanho aberto (declara menos do que tem): o que se lê de verdade passa pelo teto' do
      importar('geracao_solar')
      stub_const('Autonomia::FerramentasProntas::Bases::GeracaoSolar::MAX_ABERTO', 2_000)
      linhas = (1..800).map do |n|
        gd_linha(cep: format('%08d', 20_000_000 + n), municipio: '3509502', classe: 'Residencial', tipo: 'UFV', potencia: '3,00')
      end
      csv = "#{CSV.generate_line(FerramentasProntasBasesHelper::GD_COLUNAS, col_sep: ';', force_quotes: true)}#{linhas.join("\r\n")}\r\n"
      mentiroso = Zip::OutputStream.write_buffer { |zip| zip.put_next_entry('gd.csv') && zip.write(csv) }.string.b
      local = mentiroso.index("PK\x03\x04".b)
      central = mentiroso.index("PK\x01\x02".b)
      mentiroso[local + 22, 4] = [100].pack('V')
      mentiroso[central + 24, 4] = [100].pack('V')
      expect(Zip::File.open_buffer(StringIO.new(mentiroso)).entries.first.size).to eq(100)
      arquivo_responde(url, mentiroso, tipo: 'application/zip')

      travel 29.days
      expect(importar('geracao_solar')).to eq(:falhou)

      expect(estado.call('geracao_solar').motivo_da_falha).to eq('arquivo_grande_demais')
      expect(bases::GeracaoDistribuida.vigente.count).to eq(3)
    end

    it 'o CSV sem quebra de linha (bomba de zip numa linha só): formato mudado ao chegar no teto da linha, sem ler tudo' do
      stub_const('Autonomia::FerramentasProntas::Bases::LeituraComTeto::MAX_LINHA', 1_000)
      cabecalho = CSV.generate_line(FerramentasProntasBasesHelper::GD_COLUNAS, col_sep: ';').chomp
      zip = Zip::OutputStream.write_buffer { |saida| saida.put_next_entry('gd.csv') && saida.write("#{cabecalho};#{'X' * 5_000}") }.string
      arquivo_responde(url, zip, tipo: 'application/zip')

      expect(importar('geracao_solar')).to eq(:falhou)
      expect(estado.call('geracao_solar').motivo_da_falha).to eq('formato_mudou')
    end

    it 'chaves demais na soma (o arquivo não é o que parece): formato mudado, sem estourar a memória' do
      stub_const('Autonomia::FerramentasProntas::Bases::GeracaoSolar::MAX_CHAVES', 2)

      expect(importar('geracao_solar')).to eq(:falhou)
      expect(estado.call('geracao_solar').motivo_da_falha).to eq('formato_mudou')
    end

    it 'mensal: vence no 28º dia, pela data (a rodada das 10:47:00 pega a cópia das 10:47:30)' do
      travel 30.seconds
      importar('geracao_solar')
      importador = Autonomia::FerramentasProntas::Bases::GeracaoSolar
      copia = estado.call('geracao_solar')

      expect(importador.vencida?(copia, agora: Time.zone.parse('2026-12-08 23:59 UTC'))).to be(false)
      expect(importador.vencida?(copia, agora: Time.zone.parse('2026-12-09 10:47:00 UTC'))).to be(true)
    end
  end

  describe 'Transportadoras (RNTRC da ANTT)' do
    let(:catalogo) { 'https://dados.antt.gov.br/api/3/action/package_show?id=rntrc' }

    before do
      arquivo_responde(catalogo, antt_catalogo, tipo: 'application/json')
      arquivo_responde(FerramentasProntasBasesHelper::ANTT_CSV, antt)
    end

    it 'acha o arquivo do mês no catálogo, lê em ISO-8859-1 e do autônomo não guarda nome nem CPF' do
      expect(importar('transportadoras')).to eq(:atualizada)

      registros = bases::Transportador.vigente.order(:rntrc).map { |item| item.attributes.except('id', 'geracao', 'nome_busca') }
      expect(registros).to eq([
                                { 'rntrc' => '044031531', 'cnpj' => nil, 'nome' => nil, 'categoria' => 'autônomo', 'situacao' => 'ativo',
                                  'municipio' => 'CAMPINA GRANDE', 'uf' => 'PB', 'cadastrado_em' => Date.new(2022, 8, 22),
                                  'situacao_desde' => Date.new(2022, 8, 22), 'equiparado' => false },
                                { 'rntrc' => '050085788', 'cnpj' => FerramentasProntasBasesHelper::CNPJ_EMPRESA, 'nome' => 'TRANSPORTES EXEMPLO LTDA',
                                  'categoria' => 'empresa', 'situacao' => 'ativo', 'municipio' => 'RIBEIRÃO PRETO', 'uf' => 'SP',
                                  'cadastrado_em' => Date.new(2017, 5, 23), 'situacao_desde' => Date.new(2026, 8, 27), 'equiparado' => true },
                                { 'rntrc' => '052801722', 'cnpj' => FerramentasProntasBasesHelper::CNPJ_OUTRA, 'nome' => 'COOPERATIVA EXEMPLO',
                                  'categoria' => 'cooperativa', 'situacao' => 'pendente', 'municipio' => 'BELO HORIZONTE', 'uf' => 'MG',
                                  'cadastrado_em' => Date.new(2023, 11, 1), 'situacao_desde' => Date.new(2023, 11, 1), 'equiparado' => false }
                              ])
      expect(bases::Transportador.pluck(:nome).compact).not_to include('FULANO DE TAL')
      expect(bases::Transportador.where.not(nome: nil).pluck(:nome_busca)).to contain_exactly(' transportes exemplo ltda', ' cooperativa exemplo')
    end

    it 'nome só com CNPJ válido: o MEI sai sem o CPF; documento CPF ou categoria desconhecida não guarda nome' do
      extras = [
        %("TRANSPORTES FULANO #{FerramentasProntasBasesHelper::CPF_MEI}";"060000001";"01/01/2024";"ATIVO";) +
          %("#{FerramentasProntasBasesHelper::CNPJ_MEI}";"ETC";"";"GOIANIA";"GO";"Não";"01/01/2024"),
        %("BELTRANO DE TAL";"060000002";"01/01/2024";"ATIVO";"#{FerramentasProntasBasesHelper::CPF_MEI}";"ETC";"";"GOIANIA";"GO";"Não";"01/01/2024"),
        %("CICLANO DE TAL";"060000003";"01/01/2024";"ATIVO";"#{FerramentasProntasBasesHelper::CNPJ_OUTRA}";"XYZ";"";"GOIANIA";"GO";"Não";"01/01/2024")
      ]
      arquivo_responde(FerramentasProntasBasesHelper::ANTT_CSV, "#{antt.encode('UTF-8')}#{extras.join("\r\n")}\r\n".encode('ISO-8859-1'))

      expect(importar('transportadoras')).to eq(:atualizada)

      registros = bases::Transportador.vigente.where(rntrc: %w[060000001 060000002 060000003]).order(:rntrc).pluck(:rntrc, :nome, :cnpj, :categoria)
      expect(registros).to eq([['060000001', 'TRANSPORTES FULANO', FerramentasProntasBasesHelper::CNPJ_MEI, 'empresa'],
                               ['060000002', nil, nil, 'empresa'], ['060000003', nil, nil, 'xyz']])
      expect(bases::Transportador.pluck(:nome).compact.join).not_to include(FerramentasProntasBasesHelper::CPF_MEI, 'BELTRANO', 'CICLANO')
    end

    it 'o catálogo aponta para outro host: nada é baixado de lá' do
      fora = antt_catalogo(url: 'https://fora.exemplo.test/transportadores_rntrc_11_2026.csv', anterior: false)
      arquivo_responde(catalogo, fora, tipo: 'application/json')

      expect(importar('transportadoras')).to eq(:falhou)
      expect(estado.call('transportadoras').motivo_da_falha).to eq('formato_mudou')
      expect(a_request(:get, 'https://fora.exemplo.test/transportadores_rntrc_11_2026.csv')).not_to have_been_made
    end
  end

  describe 'Focos de queimada (INPE)' do
    let(:dias) { (0...8).map { |atras| (Date.new(2026, 11, 11) - atras).iso8601 } }
    let(:focos) { [['13:40:00', '-12.54321', '-55.71234', '5107925'], ['14:00:00', '-3.1', '-60.0', '1302603']] }

    before do
      dias.each_with_index do |dia, n|
        arquivo_responde(inpe_url(dia), inpe_dia(dia, focos.first(n.zero? ? 1 : 2)))
      end
    end

    it 'baixa os 8 dias da janela e guarda cada foco' do
      expect(importar('queimadas')).to eq(:atualizada)

      expect(bases::FocoDeQueimada.vigente.count).to eq(15)
      foco = bases::FocoDeQueimada.vigente.order(:detectado_em).last
      expect(foco).to have_attributes(detectado_em: Time.utc(2026, 11, 11, 13, 40), codigo_municipio: '5107925', bioma: 'Amazônia',
                                      satelite: 'NOAA-20')
      expect(foco.latitude.to_f).to eq(-12.543)
    end

    it 'o dia que ainda não saiu (404) é pulado sem derrubar a rodada' do
      stub_request(:get, inpe_url(dias.first)).to_return(status: 404)

      expect(importar('queimadas')).to eq(:atualizada)
      expect(bases::FocoDeQueimada.vigente.count).to eq(14)
    end

    it 'janela com muito menos focos que a anterior não é recusada (queimada varia de verdade)' do
      importar('queimadas')
      travel 1.day
      (0...8).each { |atras| stub_request(:get, inpe_url((Date.new(2026, 11, 12) - atras).iso8601)).to_return(status: 404) }
      arquivo_responde(inpe_url('2026-11-12'), inpe_dia('2026-11-12', [['01:00:00', '-12.5', '-55.7', '5107925']]))

      expect(importar('queimadas')).to eq(:atualizada)
      expect(bases::FocoDeQueimada.vigente.count).to eq(1)
    end

    it 'a segunda rodada troca a janela inteira, sem duplicar' do
      importar('queimadas')
      travel 1.day
      arquivo_responde(inpe_url('2026-11-12'), inpe_dia('2026-11-12', [['01:00:00', '-12.5', '-55.7', '5107925']]))
      importar('queimadas')

      expect(bases::FocoDeQueimada.count).to eq(14)
      expect(bases::FocoDeQueimada.distinct.pluck(:geracao)).to eq([2])
      expect(bases::FocoDeQueimada.vigente.minimum(:detectado_em)).to eq(Time.utc(2026, 11, 5, 13, 40))
    end
  end

  describe 'o download' do
    it 'só chama os hosts do importador, em HTTPS na 443' do
      download = Autonomia::FerramentasProntas::Bases::Download.new(hosts: %w[dadosabertos.ans.gov.br])

      %w[https://fora.exemplo.test/a.csv http://dadosabertos.ans.gov.br/a.csv https://dadosabertos.ans.gov.br:8443/a.csv
         https://usuario@dadosabertos.ans.gov.br/a.csv].each do |url|
        expect { download.baixar(url, max_bytes: 10, prazo: 5) }
          .to raise_error(Autonomia::FerramentasProntas::Bases::Falha, 'host_fora_da_lista')
      end
      expect(download.chamadas).to eq(0)
    end

    it 'o redirecionamento para outro host é recusado antes de sair' do
      url = 'https://dadosabertos.ans.gov.br/FTP/PDA/a.csv'
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://fora.exemplo.test/a.csv' })

      expect { Autonomia::FerramentasProntas::Bases::Download.new(hosts: %w[dadosabertos.ans.gov.br]).baixar(url, max_bytes: 100, prazo: 5) }
        .to raise_error(Autonomia::FerramentasProntas::Bases::Falha, 'redirecionou_para_fora')
      expect(a_request(:get, 'https://fora.exemplo.test/a.csv')).not_to have_been_made
    end
  end

  describe 'a busca durante a troca' do
    it 'lê a geração que vale no mesmo comando: antes da troca, a antiga inteira; depois, a nova' do
      bases::Estado.create!(base: 'planos_de_saude', geracao_ativa: 1)
      bases::Operadora.create!(geracao: 1, registro_ans: '100001')
      bases::Operadora.create!(geracao: 2, registro_ans: '200002')

      expect(bases::Operadora.vigente.pluck(:registro_ans)).to eq(['100001'])
      bases::Estado.find_by(base: 'planos_de_saude').update!(geracao_ativa: 2)
      expect(bases::Operadora.vigente.pluck(:registro_ans)).to eq(['200002'])
    end
  end
end
