# Quem pôs a conversa de e-mail numa pasta do painel, e por quê (#2616). Sem isso, a resolução de Spam e Lixeira saía
# pelo ActivityMessageHandler: no Spam automático, sem pessoa, "resolvida pelo sistema por N dias de inatividade" (o
# auto-resolve da conta nunca rodou); no toque da pessoa, "resolvida por <nome>", sem dizer para onde foi.
# Com o autor em `Current.executed_by` o handler não escreve nada (só escreve para regra de automação e contato); a
# atividade certa é a daqui, no idioma da conta. O autor fica em volta da transação inteira, porque o handler roda no
# after_update_commit, e o de antes volta no fim (como em Enterprise::Message).
module ConversaCanal::AtividadeDaPasta
  module_function

  # Sem autor (a volta para a Entrada), nada muda e a atividade é a de sempre: "reaberta por <nome>".
  def com_autor(autor)
    antes = Current.executed_by
    Current.executed_by = autor || antes
    yield
  ensure
    Current.executed_by = antes
  end

  # Pelo mesmo job do handler: no after_create_commit da conversa nova, o display_id (que vem do banco) ainda não foi
  # lido, e a mensagem criada ali sairia no evento e no webhook sem a conversa.
  def registrar!(conversa, chave, **)
    texto = I18n.t("conversa_canal.pastas.atividade.#{chave}", locale: conversa.account.locale, **)
    Conversations::ActivityMessageJob.perform_later(
      conversa, { account_id: conversa.account_id, inbox_id: conversa.inbox_id, message_type: :activity, content: texto }
    )
  end
end
