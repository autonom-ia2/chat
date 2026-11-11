# #2858 (F5): os arquivos das bases baixadas, nos specs. Tudo FICTÍCIO: CNPJ de teste (dígito verificador certo, empresa
# inventada), CPF de teste e nomes inventados. O formato (colunas, separador, codificação, a linha antes do cabeçalho do
# RAB, o JSON dentro da coluna, o ZIP da ANEEL) é o das fontes reais, conferido em 11/11/2026.
module FerramentasProntasBasesHelper
  CNPJ_EMPRESA = '11222333000181'.freeze
  CNPJ_OUTRA = '11444777000161'.freeze
  CPF_PESSOA = '12345678909'.freeze
  # O MEI: CNPJ de empresa com o CPF do dono no fim do nome, como vem nas fontes. Os dois fictícios.
  CNPJ_MEI = '33444555000181'.freeze
  CPF_MEI = '98765432100'.freeze

  ANS_CABECALHO = 'REGISTRO_OPERADORA;CNPJ;RAZAO_SOCIAL;NOME_FANTASIA;MODALIDADE;LOGRADOURO;NUMERO;COMPLEMENTO;BAIRRO;CIDADE;UF;' \
                  'CEP;DDD;TELEFONE;FAX;ENDERECO_ELETRONICO;REPRESENTANTE;CARGO_REPRESENTANTE;REGIAO_DE_COMERCIALIZACAO;' \
                  'DATA_REGISTRO_ANS'.freeze

  def ans_ativas(linhas = 3)
    corpo = (1..linhas).map do |n|
      registro = (300_000 + n).to_s
      cnpj = n == 1 ? CNPJ_EMPRESA : format('%014d', n)
      [%("#{registro}";"#{cnpj}";"SAÚDE EXEMPLO #{n} LTDA";"PLANO EXEMPLO #{n}";"Medicina de Grupo";"RUA X";"1";;"CENTRO";),
       %("Campinas";"SP";"13010000";"19";"30000000";;"contato@exemplo.test";"FULANO DE TAL #{n}";"DIRETOR";4;"2015-05-19")].join
    end
    [ANS_CABECALHO, *corpo].join("\r\n")
  end

  def ans_canceladas
    cabecalho = "#{ANS_CABECALHO};DATA_DESCREDENCIAMENTO;MOTIVO_DO_DESCREDENCIAMENTO"
    linha = [%("400001";"#{CNPJ_OUTRA}";"ODONTO EXEMPLO LTDA";;"Odontologia de Grupo";"RUA Y";"2";;"CENTRO";"São Paulo";"SP";),
             %("01001000";"11";"30000000";;"x@exemplo.test";"BELTRANA DE TAL";"SÓCIA";6;"2019-06-13";"2026-11-05";),
             %("INEXISTÊNCIA DE PRODUTO ATIVO POR MAIS DE 180 DIAS")].join
    [cabecalho, linha].join("\r\n")
  end

  RAB_COLUNAS = %w[MARCAS PROPRIETARIOS OPERADORES NR_CERT_MATRICULA NR_SERIE CD_TIPO DS_MODELO NM_FABRICANTE CD_CLS NR_PMD
                   CD_TIPO_ICAO NR_TRIPULACAO_MIN NR_PASSAGEIROS_MAX NR_ASSENTOS NR_ANO_FABRICACAO DT_VALIDADE_CVA DT_VALIDADE_CA
                   DT_CANC DS_MOTIVO_CANC CD_INTERDICAO DS_GRAVAME DT_MATRICULA TP_MOTOR QT_MOTOR TP_POUSO TP_CA CD_PROPOSITO_CAVE
                   NM_PROPOSITO_CAVE CF_OPERACIONAL DS_CATEGORIA_HOMOLOGACAO TP_OPERACAO DT_VENDA DS_MOEDA NR_PRECO_VENDA].freeze

  def rab_linha(marcas, proprietarios:, operadores: [], extra: {})
    valores = {
      'MARCAS' => marcas, 'PROPRIETARIOS' => proprietarios.to_json, 'OPERADORES' => operadores.to_json, 'NR_SERIE' => '1542',
      'DS_MODELO' => 'R66', 'NM_FABRICANTE' => 'ROBINSON HELICOPTER', 'NR_PMD' => '1225', 'CD_TIPO_ICAO' => 'R66',
      'NR_PASSAGEIROS_MAX' => '4', 'NR_ASSENTOS' => '5', 'NR_ANO_FABRICACAO' => '2020', 'DT_VALIDADE_CA' => '03112027',
      'DS_GRAVAME' => 'ALIENAÇÃO FIDUCIÁRIA  / O.J. RESTRITIVA DE TRANSFERÊNCIA', 'TP_MOTOR' => 'MOTOR TURBOEIXO',
      'TP_OPERACAO' => 'PRIVADA', 'DS_CATEGORIA_HOMOLOGACAO' => 'NORMAL'
    }.merge(extra)
    CSV.generate_line(RAB_COLUNAS.map { |coluna| valores[coluna].to_s }, col_sep: ';', force_quotes: true).chomp
  end

  # A linha antes do cabeçalho e o BOM vêm como no arquivo real. A 1ª aeronave é de empresa; a 2ª, de pessoa física.
  def rab(quantas = 3)
    empresa = [{ 'NOME' => ' AVIACAO EXEMPLO S.A', 'DOCUMENTO' => CNPJ_EMPRESA, 'PERCENTUAL' => 'Indisponível', 'UF' => 'SP' }]
    pessoa = [{ 'NOME' => 'FULANO DE TAL', 'DOCUMENTO' => CPF_PESSOA, 'PERCENTUAL' => '100', 'UF' => 'MT' }]
    linhas = [rab_linha('PRXYZ', proprietarios: empresa, operadores: pessoa), rab_linha('PTABC', proprietarios: pessoa),
              rab_linha('PPCAN', proprietarios: empresa, extra: { 'DT_CANC' => '01/02/2010', 'DS_MOTIVO_CANC' => 'PERECIMENTO',
                                                                  'DS_GRAVAME' => 'MATRICULA CANCELADA' })]
    linhas += (1..(quantas - 3)).map { |n| rab_linha("PS#{n.to_s(36).upcase.rjust(3, 'A')}", proprietarios: empresa) }
    "﻿Atualizado em: 2026-11-11\r\n#{CSV.generate_line(RAB_COLUNAS, col_sep: ';', force_quotes: true)}#{linhas.join("\r\n")}"
  end

  GD_COLUNAS = %w[DatGeracaoConjuntoDados AnmPeriodoReferencia NumCNPJDistribuidora SigAgente NomAgente CodClasseConsumo
                  DscClasseConsumo CodSubGrupoTarifario DscSubGrupoTarifario CodUFibge SigUF CodRegiao NomRegiao CodMunicipioIbge
                  NomMunicipio CodCEP SigTipoConsumidor NumCPFCNPJ CodEmpreendimento DthAtualizaCadastralEmpreend
                  SigModalidadeEmpreendimento DscModalidadeHabilitado QtdUCRecebeCredito SigTipoGeracao DscFonteGeracao DscPorte
                  MdaPotenciaInstaladaKW NomSubEstacao NumCoordESub NumCoordNSub NomTitularEmpreendimento].freeze

  def gd_linha(cep:, municipio:, classe:, tipo:, potencia:)
    valores = { 'SigUF' => 'MT', 'CodMunicipioIbge' => municipio, 'CodCEP' => "#{cep}  ", 'DscClasseConsumo' => classe,
                'SigTipoGeracao' => tipo, 'MdaPotenciaInstaladaKW' => potencia, 'SigTipoConsumidor' => 'PF',
                'NumCPFCNPJ' => '123***09', 'NomTitularEmpreendimento' => 'FULANO DE TAL', 'CodEmpreendimento' => 'GD.MT.000.000.001' }
    CSV.generate_line(GD_COLUNAS.map { |coluna| valores[coluna].to_s }, col_sep: ';', force_quotes: true).chomp
  end

  # Sorriso (MT) é 5107925 no IBGE. `extras`: linhas de enchimento (CEPs diferentes), para passar do mínimo da base.
  def gd_zip(extras: 0)
    linhas = [gd_linha(cep: '78890000', municipio: '5107925', classe: 'Residencial', tipo: 'UFV', potencia: '5,50'),
              gd_linha(cep: '78890000', municipio: '5107925', classe: 'Residencial', tipo: 'UFV', potencia: '4,50'),
              gd_linha(cep: '78890000', municipio: '5107925', classe: 'Rural', tipo: 'UFV', potencia: '75,00'),
              gd_linha(cep: '78891000', municipio: '5107925', classe: 'Comercial', tipo: 'EOL', potencia: '10,00')]
    linhas += (1..extras).map do |n|
      gd_linha(cep: format('%08d', 10_000_000 + n), municipio: '3509502', classe: 'Residencial', tipo: 'UFV', potencia: '3,00')
    end
    csv = "#{CSV.generate_line(GD_COLUNAS, col_sep: ';', force_quotes: true)}#{linhas.join("\r\n")}\r\n"
    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('empreendimento-geracao-distribuida.csv')
      zip.write(csv)
    end
    buffer.string
  end

  ANTT_CABECALHO = 'nome_transportador;numero_rntrc;data_primeiro_cadastro;situacao_rntrc;cpfcnpjtransportador;' \
                   'categoria_transportador;cep;municipio;uf;equiparado;data_situacao_rntrc'.freeze

  # Em ISO-8859-1, como o arquivo da ANTT. A 1ª é empresa; a 2ª, autônomo (pessoa física).
  def antt(quantas = 3)
    linhas = [
      %("'' TRANSPORTES EXEMPLO LTDA ''";"050085788";"23/05/2017";"ATIVO";"11.222.333/0001-81";"ETC";"14095-290";) +
        %("RIBEIRÃO PRETO";"SP";"Sim";"27/08/2026"),
      %("FULANO DE TAL";"044031531";"22/08/2022";"ATIVO";"123.***.***-09";"TAC";"58400-000";"CAMPINA GRANDE";"PB";"Não";"22/08/2022"),
      %("COOPERATIVA EXEMPLO";"052801722";"01/11/2023";"PENDENTE";"11.444.777/0001-61";"CTC";"30000-000";"BELO HORIZONTE";"MG";"Não";"01/11/2023")
    ]
    linhas += (1..(quantas - 3)).map do |n|
      %("EMPRESA #{n}";"#{format('%09d', 100_000_000 + n)}";"01/01/2020";"ATIVO";"";"ETC";"";"X";"SP";"Não";"01/01/2020")
    end
    "#{ANTT_CABECALHO}\r\n#{linhas.join("\r\n")}\r\n".encode('ISO-8859-1')
  end

  ANTT_CSV = 'https://dados.antt.gov.br/dataset/x/resource/y/download/transportadores_rntrc_10_2026.csv'.freeze

  # `anterior: false`: sem o arquivo do mês passado (o catálogo só com o endereço pedido).
  def antt_catalogo(url: ANTT_CSV, anterior: true)
    recursos = [{ format: 'PDF', url: 'https://dados.antt.gov.br/dataset/x/resource/z/download/dicionario_dados_rntrc.pdf',
                  last_modified: '2026-11-10T09:00:00' }]
    if anterior
      recursos << { format: 'CSV', url: 'https://dados.antt.gov.br/dataset/x/resource/v/download/transportadores_rntrc_09_2026.csv',
                    last_modified: '2026-10-10T09:00:00' }
    end
    recursos << { format: 'CSV', url: url, last_modified: '2026-11-10T09:09:43' }
    { success: true, result: { resources: recursos } }.to_json
  end

  INPE_CABECALHO = 'id,lat,lon,data_hora_gmt,satelite,municipio,estado,pais,municipio_id,estado_id,pais_id,numero_dias_sem_chuva,' \
                   'precipitacao,risco_fogo,bioma,frp'.freeze

  # Um dia do INPE: `focos` linhas de [hora, latitude, longitude, município IBGE].
  def inpe_dia(dia, focos)
    linhas = focos.each_with_index.map do |(hora, latitude, longitude, municipio), n|
      "id-#{n},#{latitude},#{longitude},#{dia} #{hora},NOAA-20,SORRISO,MATO GROSSO,Brasil,#{municipio},51,33,,,,Amazônia,10.5"
    end
    [INPE_CABECALHO, *linhas].join("\n")
  end

  def inpe_url(dia)
    "https://dataserver-coids.inpe.br/queimadas/queimadas/focos/csv/diario/Brasil/focos_diario_br_#{dia.delete('-')}.csv"
  end

  def arquivo_responde(url, corpo, tipo: 'text/csv')
    stub_request(:get, url).to_return(status: 200, body: corpo, headers: { 'Content-Type' => tipo })
  end

  def importar(chave)
    Autonomia::FerramentasProntas::Bases::Importacao.new(Autonomia::FerramentasProntas::Bases.buscar(chave)).call
  end
end

RSpec.configure do |config|
  config.include FerramentasProntasBasesHelper
end
