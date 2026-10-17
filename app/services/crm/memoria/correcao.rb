# W8 (#1601): a pessoa corrige o que a IA sabe. A correção vence e versiona: vira um fato `pessoa_corrigiu`,
# `confirmado` e TRAVADO; a IA, depois, só sugere ("a IA acha que mudou"). Pela API (a tela vem depois do mockup) e pelo
# campo do card ou do contato (A14): editar o campo à mão muda o que a IA lê.
#
#   Correcao.corrigir!(card:, grupo:, chave:, valor:, user:, item_ref: nil)
#   Correcao.nao_vale_mais!(fato)   Correcao.aceitar!(sugestao, user:)   Correcao.destravar!(fato)
#   Correcao.dos_campos!(registro, mudancas, attribute_model)   # hook do campo editado
#
# Edição do campo feita por integração ou por robô declarado (Crm::MemoriaConfig) não é pessoa: entra como sugestão,
# fonte `sistema`, alegada. A gravação da própria IA no campo (AttributeExtractorApplier) e a cópia da mescla de
# contatos passam dentro de `sem_correcao` e são ignoradas aqui; a edição sem ninguém logado (job, automação) também.
module Crm::Memoria::Correcao
  GRUPO_DO_MODELO = { 'contact_attribute' => 'contato', 'card_attribute' => 'pedido', 'conversation_attribute' => 'conversa' }.freeze

  module_function

  # Gravações no campo que não são correção de pessoa: a da IA (AttributeExtractorApplier) e a cópia de atributos da
  # mescla de contatos (ContactMergeAction). A marca fica no PRÓPRIO registro, e não na thread: o hook roda depois do
  # commit, que pode acontecer fora do bloco (a transação de fora, a trava do registro). O hook consome a marca.
  def sem_correcao(registro)
    registro.memoria_sem_correcao = true if registro.respond_to?(:memoria_sem_correcao=)
    yield
  end

  # A pessoa travou esta chave (no card, no contato ou na conversa do registro)?
  def travado?(card, target, record, key)
    return false if record.nil? || card.contact_id.nil?

    escopo = { card: { escopo: 'card', card_id: card.id }, contact: { escopo: 'contato' },
               conversation: { escopo: 'conversa', conversation_id: record.id } }.fetch(target.to_sym)
    Crm::MemoriaFato.vigentes.where(account_id: card.account_id, contact_id: card.contact_id, chave: key.to_s, travado: true)
                    .exists?(escopo)
  end

  # `campo`: { grupo:, chave:, valor:, item_ref: } e, no grupo conversa, `conversation:`.
  def corrigir!(card:, user:, **campo)
    grupo = campo[:grupo].to_s
    Crm::Memoria::Gravador.gravar!(
      alvo(card, grupo, campo[:conversation]).merge(
        tipo: grupo == 'decisao' ? 'decisao' : 'fato', chave: campo[:chave].to_s, item_ref: campo[:item_ref].to_s,
        valor: campo[:valor].to_s, fonte: 'pessoa_corrigiu', status: 'confirmado', travado: true, travado_por_user_id: user.id,
        gerado_por: "pessoa:#{user.id}"
      )
    )
  end

  # "Não vale mais": a versão expira (fica no histórico).
  def nao_vale_mais!(fato)
    fato.update!(expirado_em: Time.current)
  end

  # Aceitar a sugestão: vira o valor da pessoa (confirmado e travado); a sugestão sai.
  def aceitar!(sugestao, user:)
    Crm::MemoriaFato.transaction do
      novo = Crm::Memoria::Gravador.gravar!(
        sugestao.attributes.symbolize_keys.slice(:account_id, :contact_id, :escopo, :card_id, :conversation_id, :tipo, :chave, :item_ref,
                                                 :valor, :valor_json, :prova_message_ids, :prova_trecho, :vence_em)
                .merge(fonte: 'pessoa_corrigiu', status: 'confirmado', travado: true, travado_por_user_id: user.id,
                       gerado_por: "pessoa:#{user.id}")
      )
      sugestao.update!(expirado_em: Time.current)
      novo
    end
  end

  def destravar!(fato)
    fato.update!(travado: false, travado_por_user_id: nil)
  end

  # A14: o campo do card, do contato ou da conversa mudou. Só chaves do catálogo; a gravação da IA é ignorada.
  def dos_campos!(registro, mudancas, attribute_model, card:)
    return registro.memoria_sem_correcao = false if registro.try(:memoria_sem_correcao)
    return unless corrige_campo?(card)

    antes, depois = mudancas.map(&:to_h)
    catalogo = Crm::Memoria::Catalogo.da_conta(card.account)
    (antes.keys | depois.keys).each do |chave|
      next if antes[chave] == depois[chave] || !catalogo[[attribute_model, chave]]

      campo_editado!(card, GRUPO_DO_MODELO.fetch(attribute_model), chave, depois[chave], registro)
    end
  end

  # Sem ninguém logado (job, automação) não há a quem atribuir a edição: fica de fora.
  def corrige_campo?(card)
    Current.user.present? && card&.contact_id.present? && Crm::Memoria.ligada?(card.account)
  end

  def campo_editado!(card, grupo, chave, valor, registro)
    conversa = registro if registro.is_a?(Conversation)
    return apagar_campo!(card, grupo, chave, conversa) if valor.blank?
    return corrigir!(card: card, grupo: grupo, chave: chave, valor: valor, user: Current.user, conversation: conversa) if pessoa?(card)

    fraca = { tipo: 'fato', chave: chave, valor: valor.to_s, fonte: 'sistema', status: 'alegado', situacao: 'sugestao',
              gerado_por: "campo:#{Current.user&.id || 'sistema'}" }
    Crm::Memoria::Gravador.gravar!(alvo(card, grupo, conversa).merge(fraca))
  end

  # A pessoa apagou o campo: o que estava valendo deixa de valer.
  def apagar_campo!(card, grupo, chave, conversa)
    return unless pessoa?(card)

    Crm::MemoriaFato.vigentes.where(alvo(card, grupo, conversa)).where(chave: chave, item_ref: '').find_each { |fato| nao_vale_mais!(fato) }
  end

  # Quem editou é uma pessoa da conta: não é integração nem robô declarado.
  def pessoa?(card)
    user = Current.user
    return false if user.nil?

    vinculo = AccountUser.find_by(account_id: card.account_id, user_id: user.id)
    vinculo.present? && !vinculo.integration? && !Crm::Memoria.config(card.account).robo?(user.id)
  end

  def alvo(card, grupo, conversation)
    base = { account_id: card.account_id, contact_id: card.contact_id }
    case grupo
    when 'contato' then base.merge(escopo: 'contato')
    when 'conversa' then base.merge(escopo: 'conversa', conversation_id: (conversation || card.primary_conversation)&.id)
    else base.merge(escopo: 'card', card_id: card.id)
    end
  end
end
