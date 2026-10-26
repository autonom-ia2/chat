# #2211 — o que a pessoa digitou na busca, lido como telefone. Só dígitos e sinais de telefone ("11 97862-2068",
# "+55 (11) 97862-2068"); tudo pelo String#delete e start_with?, sem regex.
class SearchService::TelefoneDigitado
  MINIMO_DE_DIGITOS = 4
  MINIMO_PARA_NUMERO_COMPLETO = 10
  MAXIMO_DE_DIGITOS = 15
  # O que pode aparecer num telefone digitado, no formato do String#delete.
  SINAIS_DE_TELEFONE = '0-9 +().-'.freeze
  DDI_DO_BRASIL = '55'.freeze

  def initialize(texto)
    @texto = texto.to_s.strip
  end

  # Sem "+", o zero de tronco ("011 97862-2068") sai: o número gravado é "+5511...".
  def digitos
    @digitos ||= begin
      todos = @texto.delete('^0-9')
      @texto.start_with?('+') ? todos : sem_zero_na_frente(todos)
    end
  end

  def telefone?
    @texto.delete(SINAIS_DE_TELEFONE).empty? && digitos.length >= MINIMO_DE_DIGITOS
  end

  # Com "+" na frente, a pessoa digitou o número com o código do país: vale como está (número estrangeiro).
  def internacional?
    telefone? && @texto.start_with?('+')
  end

  # Comparado pelos dígitos. Com "+", o número começa com o que foi digitado; sem "+", os dígitos podem estar em
  # qualquer lugar. Número inteiro do Brasil vale também com e sem o nono dígito (#variantes).
  def condicao
    padrao = internacional? ? "+#{como_like}%" : "%#{como_like}%"
    ['(contacts.phone_number LIKE ? OR contacts.phone_number IN (?))', padrao, variantes]
  end

  # 0 = o número é o digitado (com ou sem o nono dígito) ou termina nos dígitos digitados (quem digita "11 97862-2068"
  # quer o "+5511978622068"), 1 = começa com eles, 2 = contém.
  def ordem
    sql = 'CASE WHEN contacts.phone_number IN (?) OR contacts.phone_number LIKE ? THEN 0 ' \
          'WHEN contacts.phone_number LIKE ? THEN 1 ELSE 2 END'
    ActiveRecord::Base.sanitize_sql_array([sql, variantes, "%#{como_like}", "+#{como_like}%"])
  end

  # O número inteiro como pode estar gravado: celular do Brasil com e sem o nono dígito, pelo mesmo critério do
  # Contacts::NinthDigitDuplicateMerger (Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer#contact_candidates). Sem
  # número inteiro, nenhuma.
  def variantes
    @variantes ||= formas_gravadas(numero_completo)
  end

  # O número inteiro, para criar o contato. Com "+", é o que a pessoa digitou. Sem "+", é do Brasil: põe o 55 se ainda
  # não tiver. nil quando ainda não dá um número inteiro.
  def numero_completo
    return unless telefone? && digitos.length >= MINIMO_PARA_NUMERO_COMPLETO

    numero = com_ddi
    # E.164, a mesma regra do Contact: até 15 dígitos, sem zero na frente.
    "+#{numero}" if numero.length <= MAXIMO_DE_DIGITOS && !numero.start_with?('0')
  end

  private

  def formas_gravadas(numero)
    return [] if numero.nil?
    return [numero] unless numero.start_with?("+#{DDI_DO_BRASIL}")

    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.contact_candidates(numero.delete_prefix('+')).map { |forma| "+#{forma}" }
  end

  def com_ddi
    return digitos if internacional? || (digitos.start_with?(DDI_DO_BRASIL) && digitos.length > 11)

    "#{DDI_DO_BRASIL}#{digitos}"
  end

  def como_like
    ActiveRecord::Base.sanitize_sql_like(digitos)
  end

  def sem_zero_na_frente(numero)
    numero = numero.delete_prefix('0') while numero.start_with?('0')
    numero
  end
end
