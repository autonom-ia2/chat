# "Trazer minha lista" (#2896): a mesma pessoa em várias linhas da planilha.
#
# Duas linhas são da mesma pessoa quando têm o mesmo telefone (com ou sem o nono dígito) ou o mesmo e-mail (sem
# diferença de maiúscula). Nunca por terem o mesmo nome.
# - Sem dado em conflito, as linhas viram UMA: a primeira fica, completada com o que só a outra tinha (nome, telefone,
#   e-mail, empresa e as outras colunas; o que a primeira já tinha não muda), e a outra sai da lista. As células da
#   conferência (`:celulas`, por alvo) são completadas do mesmo jeito: se a primeira virar problema, o conserto dela
#   leva o que veio da outra.
# - Com conflito (nome, telefone, e-mail, empresa ou qualquer outra coluna preenchidos e diferentes nas duas), a segunda
#   linha vira problema de linha repetida e guarda qual é a primeira (`:outra`), para a pessoa escolher com qual ficar.
#   As outras colunas contam porque juntar ficaria com o valor da primeira e o da outra sumiria sem ninguém ver: o
#   "Sim" de "é cliente", a cidade, o telefone da empresa ou uma informação. A coluna que só uma das linhas preencheu
#   não é conflito: completa a outra. A coluna que a pessoa mandou não guardar nem chega aqui.
#
# Com `juntar: false` (a planilha que traz seguros, E4 #2897: cada linha é um seguro da pessoa) as linhas sem conflito
# ficam todas na lista, como estão, e nenhuma é contada como juntada. O conflito continua virando problema.
#
# Recebe as linhas do validador e mexe nelas no lugar, como o passo de repetidas dele faz. Só olha linha sem erro.
class ContactImports::Trazer::MesmaPessoa
  MOTIVOS = { telefone: 'duplicate_phone_in_file', email: 'duplicate_email_in_file' }.freeze
  DO_TELEFONE = %i[normalized_phone normalized_phone_hash raw_phone_masked ninth_digit_added].freeze
  DO_EMAIL = %i[email email_hash email_masked].freeze
  DO_NOME = %i[raw_name normalized_name].freeze
  PAIS = '+55'.freeze
  COM_O_NONO_DIGITO = 11

  def initialize(linhas, juntar: true)
    @linhas = linhas
    @juntar = juntar
    @primeiras = { telefone: {}, email: {} }
  end

  # Devolve quantas linhas foram juntadas a outra.
  def call
    juntadas = Set.new.compare_by_identity
    @linhas.each do |linha|
      next if linha[:errors].present?

      meio, primeira = primeira_da_pessoa(linha)
      next lembrar(linha, linha) unless primeira

      juntadas << linha if juntou?(primeira, linha, meio)
    end
    @linhas.reject! { |linha| juntadas.include?(linha) }
    juntadas.size
  end

  private

  # [por onde as duas linhas são a mesma pessoa, a primeira linha dela] ou nil.
  def primeira_da_pessoa(linha)
    chaves(linha).each do |meio, chave|
      primeira = @primeiras[meio][chave]
      return [meio, primeira] if primeira
    end
    nil
  end

  def juntou?(primeira, linha, meio)
    if conflito?(primeira, linha)
      linha[:errors] << MOTIVOS.fetch(meio)
      linha[:outra] = primeira
      return false
    end

    completar(primeira, linha) if @juntar
    lembrar(primeira, linha)
    @juntar
  end

  def lembrar(primeira, linha)
    chaves(linha).each { |meio, chave| @primeiras[meio][chave] ||= primeira }
  end

  # { telefone: '1187650001', email: 'ana@exemplo.com.br' }, só o que a linha tem.
  def chaves(linha)
    { telefone: chave_do_telefone(linha[:normalized_phone]), email: linha[:email]&.downcase }.compact
  end

  # O número sem o código do país e sem o nono dígito: "+5511987650001" e "+551187650001" são o mesmo telefone.
  def chave_do_telefone(telefone)
    return if telefone.blank?

    local = telefone.delete_prefix(PAIS)
    local.length == COM_O_NONO_DIGITO ? local[0, 2] + local[3..] : local
  end

  def conflito?(primeira, linha)
    diferentes?(texto(primeira[:normalized_name]), texto(linha[:normalized_name])) ||
      diferentes?(chave_do_telefone(primeira[:normalized_phone]), chave_do_telefone(linha[:normalized_phone])) ||
      diferentes?(primeira[:email]&.downcase, linha[:email]&.downcase) ||
      diferentes?(texto(primeira[:company_name]), texto(linha[:company_name])) ||
      outra_coluna_diferente?(primeira, linha)
  end

  def outra_coluna_diferente?(primeira, linha)
    da_primeira = primeira[:extra_values].to_h
    linha[:extra_values].to_h.any? { |coluna, valor| diferentes?(texto(da_primeira[coluna]), texto(valor)) }
  end

  def diferentes?(primeiro, segundo)
    primeiro.present? && segundo.present? && primeiro != segundo
  end

  # Sem diferença de maiúscula, de acento nem de espaço sobrando.
  def texto(valor)
    I18n.transliterate(valor.to_s).downcase.squish
  end

  def completar(primeira, linha)
    copiar(primeira, linha, DO_NOME) if primeira[:normalized_name].blank?
    copiar(primeira, linha, DO_TELEFONE) if primeira[:normalized_phone].blank?
    copiar(primeira, linha, DO_EMAIL) if primeira[:email].blank?
    primeira[:company_name] = primeira[:company_name].presence || linha[:company_name]
    primeira[:extra_values] = completado(primeira[:extra_values].to_h, linha[:extra_values].to_h)
    completar_celulas(primeira, linha)
  end

  # Só a leitura de "Trazer minha lista" traz as células; a célula vazia da primeira ganha a da outra.
  def completar_celulas(primeira, linha)
    return unless primeira[:celulas] && linha[:celulas]

    primeira[:celulas] = completado(primeira[:celulas], linha[:celulas])
  end

  # O que a primeira já tinha fica; o que nela estava vazio, ou nem existia, vem da outra.
  def completado(da_primeira, da_outra)
    da_primeira.merge(da_outra) { |_chave, tinha, veio| tinha.to_s.strip.empty? ? veio : tinha }
  end

  def copiar(primeira, linha, campos)
    campos.each { |campo| primeira[campo] = linha[campo] }
  end
end
