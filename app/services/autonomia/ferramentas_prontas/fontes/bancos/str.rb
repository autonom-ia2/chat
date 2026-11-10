# O banco na lista de participantes do STR do Banco Central (reserva). O CSV tem cabeçalho com acento; as colunas são
# lidas pela posição: ISPB, nome reduzido, número do código, participa da Compe, acesso, nome extenso, início.
class Autonomia::FerramentasProntas::Fontes::Bancos::Str < Autonomia::FerramentasProntas::Provedor
  NOME = 'str'.freeze
  HOST = 'www.bcb.gov.br'.freeze
  ISPB = 0
  NOME_REDUZIDO = 1
  CODIGO = 2
  NOME_EXTENSO = 5

  def consultar(_consulta, params)
    codigo = params.fetch('codigo')
    linhas = get_csv('/content/estabilidadefinanceira/str1/ParticipantesSTR.csv')
    raise Falha, 'resposta_invalida' if linhas.empty?

    linha = linhas.find { |item| item[CODIGO].to_s.strip == codigo }
    raise NaoEncontrado if linha.nil?

    Autonomia::FerramentasProntas::Fontes::Bancos.banco(
      codigo: codigo, nome: exigir!(texto(linha[NOME_REDUZIDO])), nome_completo: texto(linha[NOME_EXTENSO]),
      ispb: texto(linha[ISPB])
    )
  end
end
