# O banco na lista de participantes do STR do Banco Central (reserva). O CSV tem cabeçalho com acento; as colunas são
# lidas pela posição: ISPB, nome reduzido, número do código, participa da Compe, acesso, nome extenso, início.
class Autonomia::FerramentasProntas::Fontes::Bancos::Str < Autonomia::FerramentasProntas::Provedor
  NOME = 'str'.freeze
  HOST = 'www.bcb.gov.br'.freeze
  ISPB = 0
  NOME_REDUZIDO = 1
  CODIGO = 2
  NOME_EXTENSO = 5

  def consultar(consulta, params)
    linhas = get_csv('/content/estabilidadefinanceira/str1/ParticipantesSTR.csv')
    raise Falha, 'resposta_invalida' if linhas.empty?
    return { 'bancos' => exigir!(linhas.filter_map { |linha| banco_da_linha(linha) }) } if consulta.nome == 'por_nome'

    numero = params.fetch('codigo').to_i
    linha = linhas.find { |item| Integer(item[CODIGO].to_s.strip, 10, exception: false) == numero }
    raise NaoEncontrado if linha.nil?

    banco_da_linha(linha) || raise(Falha, 'resposta_invalida')
  end

  private

  def banco_da_linha(linha)
    bancos = Autonomia::FerramentasProntas::Fontes::Bancos
    codigo = bancos.codigo(linha[CODIGO].to_s.strip)
    return unless codigo && texto(linha[NOME_REDUZIDO])

    bancos.banco(codigo: codigo, nome: texto(linha[NOME_REDUZIDO]), nome_completo: texto(linha[NOME_EXTENSO]), ispb: texto(linha[ISPB]))
  end
end
