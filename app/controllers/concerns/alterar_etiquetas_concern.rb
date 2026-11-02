# Pôr e tirar etiquetas uma a uma, sem mandar a lista inteira: na conversa (#2202, PR 3) e no contato (#2461).
# A rota de sempre (LabelConcern#create) troca a lista toda: quem grava por último apaga a etiqueta que outra
# janela, aba, pessoa ou automação pôs no meio-tempo. Aqui o servidor lê a lista dentro do lock do registro, aplica
# `por` e `tirar` e grava pelo mesmo caminho (update_labels), que mantém a mensagem de atividade, o tempo real, a
# automação e os relatórios. Quem pode é o controller que inclui que diz.
# Responde `{ payload: [lista final] }`, no formato do create.
# Etiqueta que a conta não tem cadastrada é aceita, como no labels#create (paridade de propósito): nenhuma das
# duas rotas confere o cadastro da conta.
#
# Quem inclui define `model` (o registro com Labelable) e `vista_das_etiquetas` (o create de sempre).
module AlterarEtiquetasConcern
  LIMITE = 50
  TAMANHO_MAXIMO = 255
  # A vírgula separa etiquetas na lista do taggable, e as aspas mudam como ela é lida: "a,b" viraria duas.
  CARACTERES_PROIBIDOS = [',', '"', "'"].freeze

  def update
    erro = motivo_da_recusa
    return render(json: { error: erro }, status: :unprocessable_entity) if erro

    model.with_lock do
      model.update_labels(lista_final(model.label_list))
    end
    @labels = model.label_list
    render vista_das_etiquetas
  end

  private

  def lista_final(atuais)
    sem_as_tiradas = atuais.reject { |titulo| tirar.include?(titulo.downcase) }
    novas = por.reject { |titulo| sem_as_tiradas.any? { |atual| atual.casecmp?(titulo) } }
    sem_as_tiradas + novas
  end

  def motivo_da_recusa
    return 'por e tirar precisam ser listas de nomes' unless listas_de_nomes?
    return 'diga o que pôr ou tirar' if por.empty? && tirar.empty?
    return "no máximo #{LIMITE} etiquetas por vez" if por.size + tirar.size > LIMITE
    return 'a mesma etiqueta não pode ser posta e tirada' if por.intersect?(tirar)

    nil
  end

  def listas_de_nomes?
    %i[por tirar].all? do |campo|
      valor = params[campo]
      valor.nil? || (valor.is_a?(Array) && valor.all? { |item| nome_valido?(item) })
    end
  end

  def nome_valido?(item)
    item.is_a?(String) && item.strip.present? && item.size <= TAMANHO_MAXIMO &&
      CARACTERES_PROIBIDOS.none? { |caractere| item.include?(caractere) }
  end

  def por
    @por ||= normalizar(alteracao_params[:por])
  end

  def tirar
    @tirar ||= normalizar(alteracao_params[:tirar])
  end

  def normalizar(lista)
    Array(lista).map { |titulo| titulo.strip.downcase }.uniq
  end

  def alteracao_params
    params.permit(por: [], tirar: [])
  end
end
