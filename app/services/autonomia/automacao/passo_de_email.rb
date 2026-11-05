# O passo "email" (#2414 G2): manda um e-mail ao contato do alvo pela caixa de e-mail da conta escolhida na receita.
# Abre uma conversa nova nessa caixa, como o "Nova conversa" do painel (ContactInboxBuilder + ConversationBuilder, com o
# assunto em `mail_subject`, de onde o envio lê), e a mensagem sai pelo envio de sempre da caixa (SendReplyJob,
# Email::SendOnEmailService). Caixa que trava numa conversa só (`lock_to_single_conversation`) reaproveita a dela. A
# conversa nova entra na Atribuição como qualquer outra: quem recebe é o motor único, não o passo.
#
# O contato sai do alvo (Contexto): a conversa de qualquer canal, o card ou o próprio contato. A mensagem sai como
# "Automação" (sem remetente, com a marca), como no passo "mensagem".
#
# Pula, com o motivo no registro:
# - a caixa foi apagada ou deixou de ser de e-mail;
# - contato sem e-mail, que pediu para não receber (o mesmo campo das campanhas) ou com o e-mail bloqueado na conta
#   (devolução, reclamação, descadastro: EmailSuppression, a mesma régua das campanhas);
# - valor vazio, ou assunto ou texto que ficou em branco.
# Quem ligou precisa estar na caixa (ou ser administrador) e poder começar conversa, como no "Nova conversa": no EE, a
# função só de leitura não começa. Sem isso a automação pausa, como na conversa (D1, D5).
# E-mail não tem janela. A resposta automática ("estou de férias") não volta a disparar automação: a Escuta não começa
# gatilho pela mensagem marcada como resposta automática. Sem teto de uso.
class Autonomia::Automacao::PassoDeEmail
  include ::Autonomia::Automacao::NaConversa

  CANAL = 'Channel::Email'.freeze

  def self.caixa(conta, caixa_id) = conta.inboxes.find_by(id: caixa_id, channel_type: CANAL)

  # Frase para a Receita, ao salvar: a caixa escolhida precisa ser uma caixa de e-mail da conta.
  def self.problemas_ao_salvar(conta, passo)
    return [] if caixa(conta, passo['caixa_id'])

    [I18n.t('autonomia.automacao.receita.caixa_de_email_invalida', passo: passo['id'], id: passo['caixa_id'])]
  end

  # Por que o e-mail não sairia para este contato, ou nil. O Executor e o ensaio perguntam aqui.
  def self.motivo_do_contato(conta, contato)
    email = contato&.email.to_s.strip
    return 'contato_sem_email' if email.empty?
    return 'contato_nao_recebe' if Contact.opted_out.exists?(id: contato.id)

    'email_bloqueado' if EmailSuppression.suppressed?(conta, email)
  end

  def executar
    caixa = self.class.caixa(@execucao.account, @passo['caixa_id'])
    return pulado('caixa_de_email_indisponivel') if caixa.nil?
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: {}) unless na_caixa?(caixa)

    contato = ::Autonomia::Automacao::Contexto.de(@alvo).contato
    motivo = self.class.motivo_do_contato(@execucao.account, contato)
    return pulado(motivo) if motivo

    mandar(caixa, contato)
  end

  private

  def mandar(caixa, contato)
    assunto = ::Autonomia::Automacao::Texto.new(@passo['assunto'], ::Autonomia::Automacao::Valores.new(alvo: @alvo)).montar
    texto = texto_pronto
    return pulado('faltou_valor') if assunto.nil? || texto.nil?
    return pulado('texto_vazio') if assunto.strip.empty? || texto.strip.empty?

    # Juntas: um erro na mensagem não deixa conversa vazia na caixa. O envio (SendReplyJob) sai depois do commit.
    conversa, mensagem = ActiveRecord::Base.transaction do
      aberta = abrir_conversa(caixa, contato, assunto.squish)
      [aberta, ::Messages::MessageBuilder.new(nil, aberta, content: texto, private: false, content_attributes: marca).perform]
    end
    Resultado.new(tipo: :ok, dados: { 'mensagem_id' => mensagem.id, 'conversa_id' => conversa.display_id })
  end

  # As mesmas perguntas do "Nova conversa" do painel: administrador ou membro da caixa (o controller confere), e a
  # ConversationPolicy deixa começar conversa (o EE recusa a função que só lê).
  def na_caixa?(caixa)
    usuario = @execucao.automacao.ligada_por
    account_user = usuario && @execucao.account.account_users.find_by(user_id: usuario.id)
    return false unless account_user
    return false unless account_user.administrator? || usuario.inboxes.exists?(id: caixa.id)

    ConversationPolicy.new({ user: usuario, account: @execucao.account, account_user: account_user }, Conversation).create?
  end

  # A caixa que trava numa conversa só devolve a dela: o assunto deste envio passa a ser o dela, porque o envio lê o
  # assunto da conversa.
  def abrir_conversa(caixa, contato, assunto)
    contact_inbox = ContactInbox.find_by(contact_id: contato.id, inbox_id: caixa.id) ||
                    ContactInboxBuilder.new(contact: contato, inbox: caixa, source_id: nil).perform
    parametros = ActionController::Parameters.new(status: 'open', additional_attributes: { mail_subject: assunto })
    conversa = ConversationBuilder.new(params: parametros, contact_inbox: contact_inbox).perform
    return conversa if conversa.additional_attributes.to_h['mail_subject'] == assunto

    conversa.update!(additional_attributes: conversa.additional_attributes.to_h.merge('mail_subject' => assunto))
    conversa
  end

  def pulado(motivo) = Resultado.new(tipo: :pulado, motivo: motivo, dados: {})
end
