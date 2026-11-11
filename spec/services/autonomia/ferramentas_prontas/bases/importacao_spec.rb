require 'rails_helper'

# #2858 (F5): a importação das bases baixadas. O aceite da fase, base a base:
#   - a primeira importação fica completa (todas as linhas, sem pessoa física);
#   - a segunda rodada atualiza sem duplicar (geração nova, a antiga apagada);
#   - numa falha simulada (fonte fora, formato mudado, arquivo cortado), os dados ficam e o alerta chega.
# Os arquivos são fictícios e vêm do WebMock (`FerramentasProntasBasesHelper`); nenhum pedido sai para a rede.
RSpec.describe Autonomia::FerramentasProntas::Bases::Importacao do
  let(:bases) { Autonomia::FerramentasProntas::Bases }
  let(:estado) { ->(chave) { bases::Estado.find_by(base: chave) } }
  let(:plataforma) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, :administrator, account: plataforma) }

  before do
    resolver_hosts_das_prontas
    bases.importadores.each { |importador| stub_const("#{importador.name}::MINIMO", 1) }
  end

  around do |example|
    travel_to(Time.zone.parse('2026-11-11 10:47 UTC')) do
      with_modified_env(AUTONOMIA_PRONTAS_ALERTA_CONTA_ID: plataforma.id.to_s) { example.run }
    end
  end

  def avisos
    Autonomia::Guide::Aviso.where(account: plataforma, user: admin)
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

    it 'fonte fora do ar: a cópia anterior continua valendo e a equipe recebe o alerta (log e Guia)' do
      importar('planos_de_saude')
      stub_request(:get, canceladas).to_return(status: 503, body: 'fora')
      allow(Rails.logger).to receive(:warn).and_call_original

      travel 1.day
      expect(importar('planos_de_saude')).to eq(:falhou)

      expect(operadoras.count).to eq(4)
      expect(bases::Operadora.distinct.pluck(:geracao)).to eq([1])
      expect(estado.call('planos_de_saude')).to have_attributes(geracao_ativa: 1, motivo_da_falha: 'erro_da_fonte', atualizado_em: 1.day.ago)
      expect(Rails.logger).to have_received(:warn).with(include('ALERTA base=planos_de_saude motivo=erro_da_fonte'))
      expect(avisos.sole).to have_attributes(gravidade: Autonomia::Guide::Aviso::URGENTE)
      expect(avisos.sole.texto).to include('Planos de saúde (ANS)', 'erro_da_fonte')
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

    it 'um alerta por base por dia, mesmo com duas falhas no mesmo dia' do
      stub_request(:get, ativas).to_timeout

      2.times { importar('planos_de_saude') }

      expect(avisos.count).to eq(1)
      expect(avisos.sole.texto).to include('ainda não foi baixada')
    end

    it 'sem conta da plataforma configurada, o alerta fica no log, sem quebrar' do
      stub_request(:get, ativas).to_return(status: 500)

      with_modified_env(AUTONOMIA_PRONTAS_ALERTA_CONTA_ID: nil, WHATSAPP_PROXY_ALERT_ACCOUNT_ID: nil) do
        expect(importar('planos_de_saude')).to eq(:falhou)
      end

      expect(avisos).to be_empty
    end

    it 'outra rodada da mesma base em andamento: não faz nada' do
      Redis::Alfred.set('autonomia:prontas:base:planos_de_saude', 'outra', nx: true, ex: 60)

      expect(importar('planos_de_saude')).to eq(:ocupada)
      expect(a_request(:get, ativas)).not_to have_been_made
    ensure
      Redis::Alfred.delete('autonomia:prontas:base:planos_de_saude')
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

    it 'mensal: só vence 28 dias depois' do
      importar('geracao_solar')
      importador = Autonomia::FerramentasProntas::Bases::GeracaoSolar

      expect(importador.vencida?(estado.call('geracao_solar'), agora: 27.days.from_now)).to be(false)
      expect(importador.vencida?(estado.call('geracao_solar'), agora: 28.days.from_now)).to be(true)
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

      registros = bases::Transportador.vigente.order(:rntrc).map { |item| item.attributes.except('id', 'geracao') }
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
