# OS VIAJANTES DA PROPOSTA do Seguro Viagem (#3211): confere o titular, os demais viajantes e o contato de emergência
# que o modelo mandou, e devolve os dados já limpos (CPF, telefone e CEP só com dígitos, nascimento em `Date`). Não
# chama nada e não grava nada.
#
# DADO PESSOAL. O que sai daqui vai só para o corpo da compra na Universal (`Compra.montar`): nunca para log, banco ou
# texto ao modelo. Os textos de `Falta` dizem qual dado corrigir e nunca repetem o valor recebido.
#
# Sem expressão regular: dígitos por `Parametro.digitos`, data por `Date.iso8601`, e-mail por `split('@')`.
module Autonomia::Agents::Tools::Native::SeguroViagem::Viajantes
  Falta = Autonomia::Agents::Tools::Native::SeguroViagem::Pedido::Falta
  Parametro = Autonomia::FerramentasProntas::Parametro
  Cpf = Autonomia::FerramentasProntas::Fontes::Cpf

  DIGITOS_DO_CPF = 11
  DIGITOS_DO_CEP = 8
  DIGITOS_DO_TELEFONE = [10, 11].freeze
  # O número do WhatsApp vem com o DDI do Brasil (55 + DDD + número): sai o DDI antes de contar os dígitos.
  DDI_DO_BRASIL = '55'.freeze
  PALAVRAS_DO_NOME = 2
  TITULAR = 'titular'.freeze
  DEMAIS = 'demais_viajantes'.freeze
  CONTATO = 'contato_de_emergencia'.freeze

  module_function

  # -> [viajantes, nil] ou [nil, Falta]. O titular vem primeiro, com e-mail, telefone, CEP, número e complemento.
  # `telefone_da_conversa`: o número do WhatsApp do cliente. Vale para o titular quando o modelo não mandou um telefone
  # aceito (o cliente não precisa digitar o número com que já está falando).
  def conferir(titular:, demais:, telefone_da_conversa: nil)
    titular = com_telefone_da_conversa(objeto(titular), telefone_da_conversa)
    demais = lista(demais)
    falta = falta_na_pessoa(titular, TITULAR, 'do titular') || falta_no_contato_do_titular(titular) ||
            falta_nos_demais(demais) || falta_de_cpf_repetido([titular] + demais)
    return [nil, falta] if falta

    [[pessoa(titular).merge(contato_do_titular(titular))] + demais.map { |dados| pessoa(dados) }, nil]
  end

  # -> [{ 'nome', 'telefone' }, nil] ou [nil, Falta]: quem fica no Brasil.
  def contato(dados)
    dados = objeto(dados)
    quem = texto(dados['nome'])
    return [nil, Falta.new("#{CONTATO}.nome", 'Informe o nome do contato de emergência que fica no Brasil.')] if quem.empty?

    fone = telefone(dados['telefone'])
    return [nil, Falta.new("#{CONTATO}.telefone", 'Informe o telefone do contato de emergência com DDD, 10 ou 11 dígitos.')] if fone.nil?

    [{ 'nome' => quem, 'telefone' => fone }, nil]
  end

  def falta_na_pessoa(dados, grupo, quem)
    if nome(dados).split.size < PALAVRAS_DO_NOME
      Falta.new("#{grupo}.nome_completo", "Informe o nome completo #{quem}, com nome e sobrenome.")
    elsif cpf(dados).nil?
      Falta.new("#{grupo}.cpf", "O CPF #{quem} não é válido. Confirme os 11 dígitos com o cliente.")
    elsif nascimento(dados).nil?
      Falta.new("#{grupo}.data_nascimento", "A data de nascimento #{quem} precisa ser uma data passada, no formato AAAA-MM-DD.")
    end
  end

  def falta_no_contato_do_titular(dados)
    return Falta.new("#{TITULAR}.email", 'O e-mail do titular não é válido. Confirme com o cliente.') unless email?(dados)

    if telefone(dados['telefone']).nil?
      Falta.new("#{TITULAR}.telefone", 'Informe o telefone do titular com DDD, 10 ou 11 dígitos.')
    elsif cep(dados).nil?
      Falta.new("#{TITULAR}.cep", 'Informe o CEP do endereço do titular, com 8 dígitos.')
    elsif texto(dados['numero']).empty?
      Falta.new("#{TITULAR}.numero", 'Informe o número do endereço do titular.')
    end
  end

  def falta_nos_demais(demais)
    demais.each_with_index do |dados, indice|
      falta = falta_na_pessoa(dados, DEMAIS, "do #{indice + 2}º viajante")
      return falta if falta
    end
    nil
  end

  def falta_de_cpf_repetido(pessoas)
    cpfs = pessoas.map { |dados| cpf(dados) }
    return nil if cpfs.uniq.size == cpfs.size

    Falta.new("#{DEMAIS}.cpf", 'O mesmo CPF aparece em mais de um viajante. Confirme o CPF de cada um com o cliente.')
  end

  def pessoa(dados)
    { 'nome_completo' => nome(dados), 'cpf' => cpf(dados), 'nascimento' => nascimento(dados) }
  end

  def contato_do_titular(dados)
    { 'email' => texto(dados['email']), 'telefone' => telefone(dados['telefone']), 'cep' => cep(dados),
      'numero' => texto(dados['numero']), 'complemento' => texto(dados['complemento']).presence }
  end

  # R17: `Parametro.digitos` devolve nil fora de 11 dígitos, e `Cpf.valido?` nunca recebe nil.
  def cpf(dados)
    digitos = Parametro.digitos(dados['cpf'], DIGITOS_DO_CPF)
    digitos.present? && Cpf.valido?(digitos) ? digitos : nil
  end

  def cep(dados)
    Parametro.digitos(dados['cep'], DIGITOS_DO_CEP)
  end

  def telefone(valor)
    digitos = valor.to_s.each_char.select { |caractere| caractere.between?('0', '9') }.join
    digitos = digitos.delete_prefix(DDI_DO_BRASIL) if digitos.length > DIGITOS_DO_TELEFONE.max
    DIGITOS_DO_TELEFONE.lazy.filter_map { |tamanho| Parametro.digitos(digitos, tamanho) }.first
  end

  def com_telefone_da_conversa(titular, telefone_da_conversa)
    return titular if telefone(titular['telefone']) || telefone(telefone_da_conversa).nil?

    titular.merge('telefone' => telefone_da_conversa)
  end

  # Nome e sobrenome com os espaços normalizados.
  def nome(dados)
    texto(dados['nome_completo']).split.join(' ')
  end

  # Data ISO, até hoje: nascimento no futuro não tem idade.
  def nascimento(dados)
    valor = dados['data_nascimento']
    data = valor.is_a?(String) ? Date.iso8601(valor.strip) : nil
    data if data && data <= Date.current
  rescue Date::Error
    nil
  end

  # Uma `@`, algo antes dela e um ponto no domínio, nem no começo nem no fim. Sem espaço.
  def email?(dados)
    email = texto(dados['email'])
    usuario, dominio, *sobra = email.split('@', -1)
    sobra.empty? && usuario.present? && email.exclude?(' ') && dominio.to_s.include?('.') &&
      !dominio.start_with?('.') && !dominio.end_with?('.')
  end

  def texto(valor)
    valor.is_a?(String) || valor.is_a?(Numeric) ? valor.to_s.strip : ''
  end

  def objeto(valor)
    valor.is_a?(Hash) ? valor.stringify_keys : {}
  end

  def lista(valor)
    valor.is_a?(Array) ? valor.map { |item| objeto(item) } : []
  end

  private_class_method :falta_na_pessoa, :falta_no_contato_do_titular, :falta_nos_demais, :falta_de_cpf_repetido,
                       :pessoa, :contato_do_titular, :cpf, :cep, :telefone, :nome, :nascimento, :email?, :texto,
                       :objeto, :lista
end
