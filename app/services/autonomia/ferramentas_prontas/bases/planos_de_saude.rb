# PLANOS DE SAÚDE (#2858, F5): as operadoras de plano de saúde registradas na ANS, as ativas e as canceladas. Diária.
#   - dois CSV do portal de dados abertos da ANS (PDA): `Relatorio_cadop.csv` (ativas, ~0,35 MB) e
#     `Relatorio_cadop_canceladas.csv` (~1 MB), separados por ";", em UTF-8;
#   - fica: registro na ANS, CNPJ, razão social, nome fantasia, modalidade, cidade, UF, data do registro e, da cancelada,
#     a data e o motivo. NÃO fica o representante (pessoa física), nem e-mail e telefone.
class Autonomia::FerramentasProntas::Bases::PlanosDeSaude < Autonomia::FerramentasProntas::Bases::Importador
  CHAVE = 'planos_de_saude'.freeze
  MODELO = Autonomia::FerramentasProntas::Bases::Operadora
  HOSTS = %w[dadosabertos.ans.gov.br].freeze
  FREQUENCIA = :diaria
  MINIMO = 500
  PASTA = 'https://dadosabertos.ans.gov.br/FTP/PDA'.freeze
  ATIVAS = "#{PASTA}/operadoras_de_plano_de_saude_ativas/Relatorio_cadop.csv".freeze
  CANCELADAS = "#{PASTA}/operadoras_de_plano_de_saude_canceladas/Relatorio_cadop_canceladas.csv".freeze
  MAX_BYTES = 20.megabytes
  PRAZO = 120
  COLUNAS = %w[registro_ans cnpj razao_social nome_fantasia nome_busca modalidade cidade uf registrada_em ativa cancelada_em
               motivo_do_cancelamento].freeze
  CABECALHO = %w[REGISTRO_OPERADORA CNPJ RAZAO_SOCIAL NOME_FANTASIA MODALIDADE CIDADE UF DATA_REGISTRO_ANS].freeze
  CABECALHO_CANCELADAS = (CABECALHO + %w[DATA_DESCREDENCIAMENTO MOTIVO_DO_DESCREDENCIAMENTO]).freeze

  class << self
    def baixar(download)
      { ativas: download.baixar(ATIVAS, max_bytes: MAX_BYTES, prazo: PRAZO),
        canceladas: download.baixar(CANCELADAS, max_bytes: MAX_BYTES, prazo: PRAZO) }
    end

    def linhas(arquivos)
      ativas = csv(arquivos.fetch(:ativas), colunas: CABECALHO)
      canceladas = csv(arquivos.fetch(:canceladas), colunas: CABECALHO_CANCELADAS)
      Enumerator.new do |saida|
        ativas.each { |linha| saida << operadora(linha, ativa: true) }
        canceladas.each { |linha| saida << operadora(linha, ativa: false) }
      end
    end

    def operadora(linha, ativa:)
      registro = digitos(linha['REGISTRO_OPERADORA'])
      return if registro.nil?

      razao = texto(linha['RAZAO_SOCIAL'])
      fantasia = texto(linha['NOME_FANTASIA'])
      [registro, digitos(linha['CNPJ']), razao, fantasia, Autonomia::FerramentasProntas::Lista.comparavel("#{razao} #{fantasia}"),
       texto(linha['MODALIDADE']), texto(linha['CIDADE']), texto(linha['UF']), data(linha['DATA_REGISTRO_ANS']), ativa,
       ativa ? nil : data(linha['DATA_DESCREDENCIAMENTO']), ativa ? nil : texto(linha['MOTIVO_DO_DESCREDENCIAMENTO'])]
    end
  end
end
