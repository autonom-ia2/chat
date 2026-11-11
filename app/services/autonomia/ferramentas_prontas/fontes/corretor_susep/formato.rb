# O FORMATO DA CONSULTA PÚBLICA DA SUSEP, conferido a cada resposta (o endpoint não tem documentação nem aviso de mudança):
#   { "retorno": { "totalRegistros": 1, "registros": [{ "protocolo", "nome", "situacao", "produtos", "cpfCnpj", … }] } }
# O `protocolo` de cada registro é o número do registro SUSEP; `produtos` é texto, separado por vírgula (nulo no suspenso).
#
# MUDOU O FORMATO (`mudou!`): campo que sumiu ou mudou de tipo, ou o filtro ignorado (a busca pelo CNPJ devolveu outro
# CNPJ, a do CPF outro CPF mascarado, a do nome outro nome). A fonte responde "não consegui" (`formato_mudou`, que a
# `Execucao` conta e registra) e deixa um ALERTA no log, com o campo: quem lê o log sabe o que mudou. Sem dado pessoal.
module Autonomia::FerramentasProntas::Fontes::CorretorSusep::Formato
  Falha = Autonomia::FerramentasProntas::Provedor::Falha
  NaoEncontrado = Autonomia::FerramentasProntas::Provedor::NaoEncontrado

  MAX_CORRETORES = 10
  # O CPF volta mascarado com 11 posições, e só os 6 do meio à mostra ("***444777**").
  MEIO_DO_CPF = (3..8)

  module_function

  # -> { 'total', 'mostrando'?, 'corretores' => [{ 'nome', 'situacao', 'registro_susep', 'ramos' }] }.
  def corretores(corpo, documento: nil, nome: nil)
    total, registros = retorno!(corpo)
    raise NaoEncontrado if registros.empty? && total.zero?

    mudou!('registros') if registros.empty?
    registros.each { |registro| conferir!(registro, documento, nome) }
    resumo(total, registros.map { |registro| corretor(registro) })
  end

  # -> [totalRegistros, registros].
  def retorno!(corpo)
    retorno = corpo.is_a?(Hash) ? corpo['retorno'] : nil
    mudou!('retorno') unless retorno.is_a?(Hash)
    mudou!('totalRegistros') unless retorno['totalRegistros'].is_a?(Integer)
    mudou!('registros') unless retorno['registros'].is_a?(Array)

    [retorno['totalRegistros'], retorno['registros']]
  end

  def resumo(total, itens)
    mostrados = itens.first(MAX_CORRETORES)
    { 'total' => total }.merge(total > mostrados.size ? { 'mostrando' => mostrados.size } : {}).merge('corretores' => mostrados)
  end

  def conferir!(registro, documento, nome)
    mudou!('registro') unless registro.is_a?(Hash)
    %w[protocolo nome situacao].each { |campo| mudou!(campo) if registro[campo].to_s.strip.empty? }
    mudou!('produtos') unless registro['produtos'].nil? || registro['produtos'].is_a?(String)
    filtro!(registro, documento, nome)
  end

  # O filtro pedido valeu? Voltou corretor de outro documento ou de outro nome: a SUSEP ignorou o filtro.
  def filtro!(registro, documento, nome)
    mudou!('cpfCnpj') if documento && !mesmo_documento?(registro['cpfCnpj'], documento)
    mudou!('nome') if nome && !mesmo_nome?(registro['nome'], nome)
  end

  def corretor(registro)
    { 'nome' => registro['nome'].to_s.squish, 'situacao' => registro['situacao'].to_s.squish,
      'registro_susep' => registro['protocolo'].to_s.strip, 'ramos' => registro['produtos'].to_s.split(',').map(&:squish).compact_blank }
  end

  # O CNPJ volta inteiro; o CPF, mascarado: confere o que está à mostra.
  def mesmo_documento?(devolvido, documento)
    texto = devolvido.to_s.strip
    return texto.upcase.delete('^0-9A-Z') == documento unless documento.length == 11

    texto.length == 11 && texto[MEIO_DO_CPF] == documento[MEIO_DO_CPF]
  end

  # A SUSEP procura pelo começo do nome; aqui basta cada palavra da busca estar no nome (sem acento e sem caixa).
  def mesmo_nome?(devolvido, nome)
    texto = Autonomia::FerramentasProntas::Lista.comparavel(devolvido)
    Autonomia::FerramentasProntas::Lista.comparavel(nome).split.all? { |palavra| texto.include?(palavra) }
  end

  def mudou!(campo)
    Rails.logger.warn("[autonomia][pronta] ALERTA corretor_susep: o formato da SUSEP mudou campo=#{campo}; a fonte responde " \
                      '"não consegui" até o adaptador ser revisto')
    raise Falha, 'formato_mudou'
  end
end
