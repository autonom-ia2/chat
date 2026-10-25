# Nome genérico refinado uma vez (#2163, flag `crm_ia_nome_provisorio`).
#
# Quando o pedido chega com pouca informação ("quero outra cotação"), o modelo maior dá um nome genérico ("Nova cotação")
# e diz que ele é genérico (`nome_generico` no schema do Crm::Subjects::Reviewer). Quem decide é o modelo; o código só
# guarda a marca no card (metadata `subject.provisorio`, com o nome dado) e confere, pelo dado, se ela ainda vale:
#
# - provisório: a IA deu o nome e disse que ele é genérico;
# - ninguém mexeu: o título é o mesmo que a IA deu e nenhuma pessoa editou o card depois (atividade `update` de usuário).
#
# Com a marca valendo, o detalhe que chega no mesmo pedido troca o nome UMA vez pelo específico, no mesmo card: o modelo
# responde "o mesmo assunto" com o nome novo. O nome refinado não leva a marca: não muda de novo.
#
# O card sem nome que já carregava um pedido (houve decisão "o mesmo assunto" nele, `MESMO_ASSUNTO` no reason) também
# ganha nome pelo "o mesmo assunto"; o pedido novo no mesmo funil vira outro card, em vez de apagar o primeiro pedido.
module Crm::Subjects::NomeProvisorio
  FLAG = 'crm_ia_nome_provisorio'.freeze
  # O reason da decisão "o mesmo assunto" (só com a flag): o card em foco carrega um pedido.
  MESMO_ASSUNTO = 'mesmo_assunto'.freeze
  # O reason do nome refinado e do card novo no lugar da troca de nome, para medir.
  REFINADO = 'nome_refinado'.freeze
  JA_TINHA_PEDIDO = 'card_ja_tinha_pedido'.freeze
  # O "mesmo assunto" do Jev vai ao modelo maior para pedir o nome (review_reason `nome_provisorio`) no máximo estas
  # vezes por card: se o detalhe não chega, o custo para. O pedido novo e a certeza baixa seguem indo ao modelo maior.
  TENTATIVAS = 3

  module_function

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # O bloco `subject` do metadata. provisorio: o nome é genérico e pode ser refinado uma vez; guarda o nome dado, que é
  # a referência para saber se uma pessoa o trocou.
  def subject(source, titulo: nil, provisorio: false)
    base = { 'source' => source, 'named_at' => Time.current.iso8601 }
    provisorio ? base.merge('provisorio' => true, 'titulo' => titulo) : base
  end

  # O nome do card ainda é o genérico que a IA deu, e ninguém mexeu nele.
  def refinavel?(card)
    return false unless card&.open? && ligada?(card.account)

    marca = card.metadata.to_h['subject'].to_h
    marca['source'] == 'ai' && marca['provisorio'] == true && marca['titulo'] == card.title && !pessoa_editou?(card, marca)
  end

  # O card sem nome em que já houve "o mesmo assunto": ele carrega um pedido, mesmo sem nome.
  def carrega_pedido?(card)
    return false if card.nil? || !ligada?(card.account) || Crm::Subjects::Naming.named?(card)

    Crm::SubjectDecision.exists?(card_id: card.id, reason: MESMO_ASSUNTO)
  end

  # Ainda cabe perguntar o nome ao modelo maior pelo "mesmo assunto" deste card (TENTATIVAS). Conta as perguntas da
  # conversa desde que o card ganhou o nome, inclusive as que falharam (sem card na decisão): todas custaram.
  def tentativa_livre?(card, conversation)
    desde = Time.zone.parse(card.metadata.to_h.dig('subject', 'named_at').to_s) || card.created_at
    Crm::SubjectDecision.where(conversation_id: conversation.id, review_reason: 'nome_provisorio', created_at: desde..)
                        .count < TENTATIVAS
  end

  # O assunto atual pode ganhar nome (ou o nome específico) pela resposta "o mesmo assunto".
  def nomeavel?(card)
    refinavel?(card) || carrega_pedido?(card)
  end

  def pessoa_editou?(card, marca)
    desde = Time.zone.parse(marca['named_at'].to_s)
    atividades = Crm::Activity.where(card_id: card.id, actor_type: 'user', event_type: 'update')
    desde ? atividades.exists?(created_at: desde..) : atividades.exists?
  end
  private_class_method :pessoa_editou?
end
