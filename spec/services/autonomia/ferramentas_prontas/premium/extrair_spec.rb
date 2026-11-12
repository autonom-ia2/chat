require 'rails_helper'

# #2858 (F7): o que sai do dado da BigDataCorp para o agente, card a card, com dados fictícios no formato da
# documentação pública. Prova que ficam de fora: parentes, sócios pessoa física, partes dos processos, nome do dono do
# carro, pessoa exposta politicamente, doação eleitoral, link de arquivo e contato pessoal.
RSpec.describe Autonomia::FerramentasProntas::Premium::Extrair do
  let(:catalogo) { Autonomia::FerramentasProntas::Catalogo }
  let(:leitura) { Autonomia::FerramentasProntas::Premium::Leitura }

  def dataset(card, consulta)
    catalogo.buscar(card).consulta(consulta).dataset
  end

  def ler(card, consulta, dado, **)
    alvo = dataset(card, consulta)
    leitura.de(alvo, corpo_da_bigdatacorp(alvo.nome, alvo.resposta, dado, **))
  end

  it 'CADIN: o resultado da fonte, sem o link do arquivo' do
    dado = [{ 'Origin' => 'CADIN', 'QueryResultData' => { 'Content' => 'Nada consta para o CNPJ', 'State' => 'SP',
                                                          'RawResultFile' => 'https://arquivo.exemplo.test/c.html' } }]
    resultado = ler('certidoes_empresa', 'cadin', dado)
    expect(resultado.dados).to eq('resultado' => 'Nada consta para o CNPJ', 'uf' => 'SP')
  end

  it 'FGTS e trabalhista: situação e datas, sem o texto da certidão' do
    fgts = [{ 'BaseStatus' => 'REGULAR', 'AdditionalOutputData' => { 'Validity' => '01/11/2026 - 30/11/2026', 'CertificateText' => 'longo' } }]
    expect(ler('certidoes_empresa', 'fgts', fgts).dados).to eq('situacao' => 'REGULAR', 'periodo' => '01/11/2026 - 30/11/2026')
    cndt = [{ 'BaseStatus' => 'NAO CONSTA', 'AdditionalOutputData' => { 'IsInDebt' => 'False', 'Expiration' => '10/05/2027',
                                                                        'RawCertificateText' => 'longo' } }]
    expect(ler('certidoes_empresa', 'trabalhista', cndt).dados).to eq('situacao' => 'NAO CONSTA', 'em_debito' => false,
                                                                      'vence_em' => '10/05/2027')
  end

  it 'processos: contagem e dados do processo, sem as partes' do
    dado = { 'Last365DaysLawsuits' => 1, 'LastLawsuitDate' => '2026-01-10T00:00:00Z',
             'Lawsuits' => [{ 'Number' => '0000000-00.2026.8.26.0000', 'CourtName' => 'TJSP', 'Type' => 'CIVEL', 'Status' => 'ATIVO',
                              'Parties' => [{ 'Name' => 'FULANO EXEMPLO', 'Doc' => '11144477735' }] }] }
    dados = ler('raio_x_empresa', 'processos', dado).dados
    expect(dados['total']).to eq(1)
    expect(dados['processos'].sole).to eq('numero' => '0000000-00.2026.8.26.0000', 'tribunal' => 'TJSP', 'tipo' => 'CIVEL',
                                          'situacao' => 'ATIVO')
    expect(dados.to_json).not_to include('FULANO', '11144477735')
  end

  it 'sanções: só sanções; pessoa exposta politicamente e doação eleitoral ficam de fora' do
    dado = { 'IsCurrentlySanctioned' => true, 'IsCurrentlyPEP' => true, 'TotalElectoralDonations' => 3,
             'SanctionsHistory' => [{ 'Source' => 'CEIS', 'StandardizedSanctionType' => 'IMPEDIMENTO', 'StartDate' => '2025-01-01' }] }
    dados = ler('raio_x_empresa', 'sancoes', dado).dados
    expect(dados).to eq('sancionada_hoje' => true,
                        'sancoes' => [{ 'fonte' => 'CEIS', 'tipo' => 'IMPEDIMENTO', 'inicio' => '2025-01-01' }])
  end

  it 'grupo econômico: só as empresas; pessoa física entra só na contagem' do
    dado = { 'TotalCompaniesRelationships' => 1, 'TotalPeopleRelationships' => 1,
             'CurrentRelationships' => [
               { 'RelatedEntityName' => 'EMPRESA EXEMPLO LTDA', 'RelatedEntityTaxIdNumber' => '11222333000181',
                 'RelatedEntityTaxIdType' => 'CNPJ', 'RelationshipName' => 'COLIGADA' },
               { 'RelatedEntityName' => 'SOCIO EXEMPLO', 'RelatedEntityTaxIdNumber' => '11144477735', 'RelatedEntityTaxIdType' => 'CPF' }
             ] }
    dados = ler('raio_x_empresa', 'grupo_economico', dado).dados
    expect(dados['empresas']).to eq([{ 'nome' => 'EMPRESA EXEMPLO LTDA', 'cnpj' => '11222333000181', 'relacao' => 'COLIGADA' }])
    expect(dados['pessoas_no_grupo']).to eq(1)
    expect(dados.to_json).not_to include('SOCIO EXEMPLO', '11144477735')
  end

  it 'crescimento e obras: números e registros da empresa' do
    expect(ler('raio_x_empresa', 'crescimento', { 'YearOverYearGrowthRateStatus1YearAgo' => 'GROWING', 'AverageQtyEmployees' => 12 }).dados)
      .to eq('crescimento_1_ano' => 'GROWING', 'funcionarios' => 12)
    obras = { 'TotalNumberOfRecords' => 1, 'Records' => [{ 'CNO' => '000000000000', 'City' => 'CAMPINAS', 'State' => 'SP' }] }
    expect(ler('raio_x_empresa', 'obras', obras).dados)
      .to eq('total' => 1, 'obras' => [{ 'cno' => '000000000000', 'cidade' => 'CAMPINAS', 'uf' => 'SP' }])
  end

  it 'nome e nascimento: só os dois; mãe, pai e sexo ficam de fora' do
    dado = { 'Name' => 'PESSOA EXEMPLO', 'BirthDate' => '1990-05-01T00:00:00Z', 'MotherName' => 'MAE EXEMPLO', 'FatherName' => 'PAI EXEMPLO',
             'Gender' => 'F', 'TaxIdStatus' => 'REGULAR' }
    expect(ler('conferir_pessoa', 'nome_e_nascimento', dado).dados).to eq('nome' => 'PESSOA EXEMPLO', 'nascimento' => '1990-05-01')
  end

  it 'situação do CPF: só a situação, sem nome nem óbito' do
    dado = [{ 'BaseStatus' => 'REGULAR', 'AdditionalOutputData' => { 'Name' => 'PESSOA EXEMPLO', 'IsDead' => 'FALSE' } }]
    expect(ler('conferir_pessoa', 'situacao_cpf', dado).dados).to eq('situacao_na_receita' => 'REGULAR')
  end

  it 'conselho de classe: registro, categoria e situação' do
    dado = { 'TotalActiveMemberships' => 1, 'Memberships' => [{ 'OrganizationName' => 'CRM', 'OrganizationChapter' => 'SP', 'Category' => 'MEDICO',
                                                                'RegistrationId' => '000000', 'Status' => 'ATIVO',
                                                                'NameRegisteredInOrganization' => 'PESSOA EXEMPLO' }] }
    expect(ler('conferir_pessoa', 'conselho', dado).dados)
      .to eq('registros_ativos' => 1, 'registros' => [{ 'conselho' => 'CRM', 'uf' => 'SP', 'categoria' => 'MEDICO', 'registro' => '000000',
                                                        'situacao' => 'ATIVO' }])
  end

  it 'placa: veículo, restrições e donos, sem o nome do dono' do
    dado = { 'TotalOwnersInLifetime' => 2, 'CurrentlyHasRestrictions' => false,
             'VehicleInfo' => [{ 'Brand' => 'GM', 'Model' => 'ONIX', 'ModelYear' => '2020', 'Chassi' => '*****00000' }],
             'VehicleHistory' => [{ 'Color' => 'PRATA', 'State' => 'SP', 'OwnerFirstName' => 'DONO EXEMPLO' }] }
    dados = ler('historico_placa', 'placa', dado).dados
    expect(dados).to include('marca' => 'GM', 'modelo' => 'ONIX', 'ano_do_modelo' => '2020', 'donos_ao_longo_da_vida' => 2,
                             'restricao_hoje' => false, 'historico' => [{ 'cor' => 'PRATA', 'uf' => 'SP' }])
    expect(dados.to_json).not_to include('DONO EXEMPLO', 'Chassi')
  end

  it 'área de risco com a legenda, criminalidade da cidade e vistoria' do
    expect(ler('risco_endereco', 'area_de_risco', { 'Point' => 3, 'Radius100m' => 2 }).dados)
      .to include('no_ponto' => 3, 'raio_100m' => 2, 'legenda' => include('fora de comunidade'))
    crimes = { 'City' => 'SAO PAULO', 'State' => 'SP', 'TotalLast360DaysOccurrences' => 100,
               'CriminalOccurrencesByNature' => [{ 'CriminalNature' => 'FURTO', 'Last360DaysOccurrences' => 60 }] }
    expect(ler('risco_endereco', 'criminalidade', crimes).dados)
      .to eq('cidade' => 'SAO PAULO', 'uf' => 'SP', 'ocorrencias_12_meses' => 100,
             'tipos_de_crime' => [{ 'tipo' => 'FURTO', 'ocorrencias_12_meses' => 60 }])
    expect(ler('risco_endereco', 'vistoria', { 'Tipology' => 'APARTAMENTO', 'PropertyAreaInM2' => 33, 'Complement' => 'APTO 1' }).dados)
      .to eq('tipo' => 'APARTAMENTO', 'area_m2' => 33)
  end

  it 'CAR sem o desenho do terreno; embargo do IBAMA com a lista' do
    car = { 'PropertyCode' => FerramentasPremiumHelper::CAR_EXEMPLO, 'RegistrationStatus' => 'ATIVO', 'UF' => 'MT',
            'LegalReserve' => { 'Total de reserva legal declarada' => '10,5' }, 'SerializedGeoJsonGeometry' => '{"type":"x"}' }
    expect(ler('imovel_rural', 'car', car).dados).to eq('codigo' => FerramentasPremiumHelper::CAR_EXEMPLO, 'situacao' => 'ATIVO',
                                                        'uf' => 'MT', 'reserva_legal_ha' => '10,5')
    embargo = [{ 'BaseStatus' => 'EXISTE PENDÊNCIA DE EMBARGO',
                 'AdditionalOutputData' => { 'Embargo' => { '1' => { 'Number' => '000000', 'AreaCity' => 'MANAUS', 'AreaUF' => 'AM' } },
                                             'EvidenceFileLink' => 'https://arquivo.exemplo.test/e.pdf' } }]
    expect(ler('imovel_rural', 'embargo_ibama', embargo).dados)
      .to eq('situacao' => 'EXISTE PENDÊNCIA DE EMBARGO', 'embargos' => [{ 'numero' => '000000', 'cidade' => 'MANAUS', 'uf' => 'AM' }])
  end

  it 'contato da empresa: sem telefone na lista "não perturbe" nem e-mail pessoal, até 3 de cada' do
    fones = { 'Phones' => [{ 'AreaCode' => '11', 'Number' => '30000000', 'Type' => 'WORK', 'IsMainForEntity' => true },
                           { 'AreaCode' => '11', 'Number' => '90000000', 'IsInDoNotCallList' => true }] }
    expect(ler('contato_empresa', 'telefone', fones).dados)
      .to eq('telefones' => [{ 'telefone' => '11 30000000', 'tipo' => 'WORK', 'principal' => true }])
    emails = { 'Emails' => [{ 'EmailAddress' => 'contato@exemplo.test', 'Type' => 'corporate' },
                            { 'EmailAddress' => 'pessoa@exemplo.test', 'Type' => 'personal' }] }
    expect(ler('contato_empresa', 'email', emails).dados).to eq('emails' => [{ 'email' => 'contato@exemplo.test' }])
    expect(ler('contato_empresa', 'empresas_na_regiao', { 'TotalCompanies' => 10, 'TotalActiveCompanies' => 8 }).dados)
      .to eq('empresas' => 10, 'ativas' => 8)
  end

  it 'contato de MEI ou EI: o telefone sai sempre, mesmo celular ou pessoal (decisão do Rodrigo, 11/11)' do
    fones = { 'Phones' => [{ 'AreaCode' => '11', 'Number' => '990000000', 'Type' => 'MOBILE' },
                           { 'AreaCode' => '21', 'Number' => '980000000', 'Type' => 'PERSONAL' }] }

    expect(ler('contato_empresa', 'telefone', fones).dados)
      .to eq('telefones' => [{ 'telefone' => '11 990000000', 'tipo' => 'MOBILE' }, { 'telefone' => '21 980000000', 'tipo' => 'PERSONAL' }])
  end

  describe 'nada que leve a leitura errada (as fixtures da vitrine, 11/11)' do
    it 'data com hora vira só a data; a data americana das obras vira a do servidor; o fim 9999 (sem fim) sai' do
      processos = { 'FirstLawsuitDate' => '2019-03-12T10:00:00', 'Lawsuits' => [{ 'Number' => '1', 'LastMovementDate' => '2026-10-01T09:00:00' }] }
      expect(ler('raio_x_empresa', 'processos', processos).dados)
        .to include('primeiro' => '2019-03-12', 'processos' => [{ 'numero' => '1', 'ultima_movimentacao' => '2026-10-01' }])
      sancoes = { 'LastSanctionDate' => '2024-03-01T00:00:00',
                  'SanctionsHistory' => [{ 'Source' => 'ceis', 'StartDate' => '2024-03-01T00:00:00', 'EndDate' => '9999-12-31T23:59:59.9999999' }] }
      expect(ler('raio_x_empresa', 'sancoes', sancoes).dados)
        .to eq('ultima_sancao' => '2024-03-01', 'sancoes' => [{ 'fonte' => 'ceis', 'inicio' => '2024-03-01' }])
      obras = { 'Records' => [{ 'CNO' => '9', 'StartDate' => '02/20/2025 00:00:00' }] }
      expect(ler('raio_x_empresa', 'obras', obras).dados['obras']).to eq([{ 'cno' => '9', 'inicio' => '2025-02-20' }])
      pgfn = [{ 'BaseStatus' => 'NEGATIVA', 'AdditionalOutputData' => { 'EmissionDate' => '2026-11-10 10:00:00Z' } }]
      expect(ler('certidoes_empresa', 'divida_uniao', pgfn).dados).to eq('situacao' => 'NEGATIVA', 'emitida_em' => '2026-11-10')
    end

    it 'o valor da causa desconhecido (-1 na BigDataCorp) sai; o conhecido vai como valor_da_causa' do
      dado = { 'Lawsuits' => [{ 'Number' => '1', 'Value' => -1 }, { 'Number' => '2', 'Value' => 15_000.0 }] }
      expect(ler('raio_x_empresa', 'processos', dado).dados['processos'])
        .to eq([{ 'numero' => '1' }, { 'numero' => '2', 'valor_da_causa' => 15_000.0 }])
    end

    it 'o "False" e o "True" em texto da certidão trabalhista viram sim ou não' do
      cndt = [{ 'BaseStatus' => 'NAO CONSTA', 'AdditionalOutputData' => { 'IsInDebt' => 'False' } }]
      expect(ler('certidoes_empresa', 'trabalhista', cndt).dados).to eq('situacao' => 'NAO CONSTA', 'em_debito' => false)
    end
  end

  it 'formato que mudou vira falha (não conta), nunca exceção' do
    resultado = ler('contato_empresa', 'telefone', { 'Phones' => 'texto' })
    expect(resultado.situacao).to eq('sem_registro')
    quebrado = ler('raio_x_empresa', 'processos', 'texto em vez de objeto')
    expect(quebrado.situacao).to eq('falha')
    expect(quebrado.motivo).to eq('resposta_invalida')
  end

  # Revisor (leitura.rb:82): o `rescue NoMethodError, TypeError, ArgumentError` escondia defeito nosso como "a BigDataCorp
  # mudou o formato". A forma do dado é conferida antes (lista nas consultas sob demanda, objeto nas outras); o defeito
  # dentro do `extrair` sobe.
  it 'a forma errada do dado (lista no lugar do objeto, objeto no lugar da lista) é resposta inválida' do
    expect(ler('historico_placa', 'placa', [{ 'VehicleInfo' => [] }])).to have_attributes(situacao: 'falha', motivo: 'resposta_invalida')
    expect(ler('certidoes_empresa', 'divida_uniao', { 'BaseStatus' => 'NEGATIVA' }))
      .to have_attributes(situacao: 'falha', motivo: 'resposta_invalida')
  end

  it 'defeito nosso dentro do extrair sobe, em vez de virar resposta inválida' do
    alvo = dataset('raio_x_empresa', 'processos')
    allow(alvo).to receive(:extrair).and_return(->(_dado) { raise NoMethodError, 'defeito nosso' })

    expect { leitura.de(alvo, corpo_da_bigdatacorp(alvo.nome, alvo.resposta, { 'Lawsuits' => [] })) }
      .to raise_error(NoMethodError, 'defeito nosso')
  end

  it 'outro código negativo da BigDataCorp é falha com o código, e a fonte lenta pela mensagem também' do
    expect(ler('raio_x_empresa', 'sancoes', nil, code: -1203, message: 'DATASET TEMPORARILY DISABLED').motivo).to eq('status_1203')
    expect(ler('raio_x_empresa', 'sancoes', nil, code: -9999, message: 'DATASET IS TOO SLOW').motivo).to eq('fonte_lenta')
  end
end
