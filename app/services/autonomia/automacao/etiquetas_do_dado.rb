# G29 (#2702): a etiqueta com o nome de um dado (`{"$valor": "card.anuncio"}` no "Pôr" ou no "Tirar" de etiquetas).
# O dado lido vira etiqueta pela regra da tela de etiquetas (EtiquetaDoTexto): "Black Friday, 50% off" sai
# "black_friday_50_off". As etiquetas escolhidas da lista ficam como estão: a tela só oferece as que existem.
#
# O texto original fica onde a pessoa olha: a etiqueta é cadastrada na conta com ele na descrição, que aparece ao passar
# o mouse sobre ela no contato e na conversa. Só quando quem ligou a automação pode cadastrar etiqueta (`label_manage`,
# a mesma chave da tela) e a etiqueta ainda não existe: a automação nunca faz o que a pessoa não poderia.
class Autonomia::Automacao::EtiquetasDoDado
  ACOES = ['PATCH conversations/:conversation_id/labels/alterar', 'PATCH contacts/:contact_id/labels/alterar'].freeze
  CAMPOS = %w[por tirar].freeze
  PERMISSAO = 'label_manage'.freeze
  # O corpo com as etiquetas prontas, o texto de cada uma, ou o motivo do pulo.
  Pronto = Struct.new(:corpo, :originais, :motivo, keyword_init: true)

  def self.aplica?(acao) = ACOES.include?(acao)

  # `receita`: o corpo como está na receita (onde estão os dados); `montado`: o mesmo corpo com os dados já lidos.
  def self.preparar(receita, montado)
    originais = {}
    corpo = ::Autonomia::Automacao::Corpo.lugares(receita.to_h).reduce(montado) do |atual, (onde, _folha)|
      next atual unless CAMPOS.include?(onde.first.to_s)

      texto = atual.dig(*onde).to_s
      etiqueta = ::Autonomia::Automacao::EtiquetaDoTexto.de(texto)
      return Pronto.new(motivo: 'etiqueta_sem_nome_valido') if etiqueta.nil?

      originais[etiqueta] = texto
      trocado(atual, onde, etiqueta)
    end
    Pronto.new(corpo: corpo, originais: originais)
  end

  # O corpo com o valor trocado no lugar (`onde`: as chaves e os índices até ele), sem mexer no original.
  def self.trocado(corpo, onde, valor)
    chave, *resto = onde
    novo = resto.empty? ? valor : trocado(corpo[chave], resto, valor)
    return corpo.merge(chave => novo) unless corpo.is_a?(Array)

    corpo.each_with_index.map { |item, indice| indice == chave ? novo : item }
  end

  def self.cadastrar(originais, account:, account_user:)
    return if originais.empty? || !account_user&.permission_granted?(PERMISSAO)

    existentes = account.labels.where(title: originais.keys).pluck(:title)
    originais.except(*existentes).each do |titulo, texto|
      account.labels.create!(title: titulo, description: texto)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      # Outra execução cadastrou a mesma etiqueta no meio-tempo: a etiqueta já está no contato, falta só a descrição.
      Rails.logger.info("[automacao][etiqueta] nao_cadastrada conta=#{account.id} #{e.class}")
    end
  end
end
