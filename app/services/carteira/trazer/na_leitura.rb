# "Trazer minha lista" com seguros (E4, #2897): o que a leitura da planilha faz a mais quando a pessoa disse que a
# planilha tem seguros. É o único ponto que o validador de "Trazer minha lista" (ContactImports::Trazer::Validador)
# chama; sem a resposta "sim" numa conta com a carteira, `da` devolve nil e a leitura é a de sempre.
#
# - `conferir`: aponta as linhas cujo seguro precisa da pessoa (Carteira::Trazer::ProblemasDeSeguro). Só quando as
#   quatro colunas obrigatórias já foram escolhidas: antes disso toda linha "faltaria" tudo.
# - `resolver_tipos`: decide o tipo de cada ramo distinto das linhas boas (Carteira::Trazer::TipoDoRamo). Pode chamar o
#   modelo, por isso o validador chama fora da transação que grava o resultado.
# - `opcoes`: as opções da importação com os tipos resolvidos (só resumo do ramo => tipo, nunca o texto).
# - `resumo`: contagens para o `validation_summary`, todas de PESSOAS ou de linhas repetidas; os contadores de linha
#   do importador não mudam. `pessoas_distintas`: as linhas boas juntadas por telefone ou e-mail (as linhas da mesma
#   pessoa não viram uma só neste modo); `pessoas_que_ja_estavam`: quantas dessas a conta já tinha;
#   `seguros_repetidos`: linhas iguais a outra, que saíram.
class Carteira::Trazer::NaLeitura
  RAMO = 'seguro_tipo'.freeze
  DA_PESSOA = %i[normalized_phone_hash email_hash].freeze

  # extras: [{ 'index' => 4, 'key' => 'Apólice' }], as colunas que não são alvo, como o leitor as entrega.
  def self.da(importacao, extras)
    colunas = Carteira::Trazer::ColunasDeSeguro.da_leitura(importacao, extras)
    new(importacao, colunas) if colunas
  end

  def initialize(importacao, colunas)
    @importacao = importacao
    @colunas = colunas
    @repetidos = 0
  end

  # linhas: as do validador, mexidas no lugar.
  def conferir(linhas)
    @repetidos = Carteira::Trazer::ProblemasDeSeguro.new(@colunas).marcar(linhas) if @colunas.completas?
  end

  def resolver_tipos(linhas)
    return unless @colunas.completas?

    ramos = linhas.select { |linha| linha[:errors].empty? }.filter_map { |linha| linha[:extra_values].to_h[@colunas.chave(RAMO)] }
    @tipos = Carteira::Trazer::TipoDoRamo.new(@importacao).resolver(ramos)
  end

  def opcoes(opcoes)
    return opcoes unless @tipos

    marca = ContactImports::Trazer::Conferencia::CHAVE
    opcoes.merge(marca => opcoes[marca].to_h.merge(Carteira::Trazer::TipoDoRamo::CHAVE => @tipos))
  end

  # validas: as linhas boas do validador ({ row_number:, normalized_phone:, normalized_phone_hash:, email:, email_hash: }).
  def resumo(validas)
    pessoas = pessoas_de(validas)
    ja_tinha = ContactImports::ExistingContacts.new(@importacao.account, validas).custom_attributes_by_row.keys.to_set
    { pessoas_distintas: pessoas.size, pessoas_que_ja_estavam: pessoas.count { |linhas| linhas.any? { |numero| ja_tinha.include?(numero) } },
      seguros_repetidos: @repetidos }
  end

  private

  # [[números das linhas de uma pessoa], ...]: a mesma pessoa é quem tem o mesmo telefone ou o mesmo e-mail.
  def pessoas_de(validas)
    de_quem = {}
    validas.each_with_object([]) do |linha, pessoas|
      marcas = linha.values_at(*DA_PESSOA).compact
      pessoa = marcas.filter_map { |marca| de_quem[marca] }.first || (pessoas << []).last
      pessoa << linha[:row_number]
      marcas.each { |marca| de_quem[marca] ||= pessoa }
    end
  end
end
