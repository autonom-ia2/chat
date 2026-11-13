# O passo "Pôr na lista de e-mail" (G52, #2760; exemplo 20, passo 9: "coloca o cliente na campanha de e-mail 'Dicas do
# mês'"). Põe o contato do alvo (conversa, card ou contato) na lista de e-mail escolhida, que é pôr a etiqueta da lista
# nele (EmailList). A campanha de e-mail com a lista vai para quem está nela na hora do envio.
#
# A etiqueta entra pelo mesmo caminho do "Pôr e tirar etiqueta do contato" (AlterarEtiquetasConcern): a lista lida
# dentro do lock do contato e gravada por `update_labels`, que mantém a atividade, o tempo real, as automações e os
# relatórios. Quem fez fica assinado pela automação (Ato).
#
# Age como quem ligou, conferido a cada execução: precisa de campaign_manage (a mesma chave de criar a lista na tela de
# campanhas) e de poder mudar o contato (ContactPolicy#update?, Acesso#alcanca?). Sem isso, a automação pausa
# (`sem_acesso`), como nos outros passos.
#
# Contato que pediu para não receber (opt-out) entra na lista mesmo assim (decisão da G52): a lista diz de quem é o
# interesse, e o envio confere a recusa e o descadastro (EmailLists::Recipients, EmailSuppression) na hora de mandar.
# Quem voltar a aceitar recebe as próximas campanhas sem precisar entrar de novo.
class Autonomia::Automacao::PassoDeListaDeEmail
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  PERMISSAO = 'campaign_manage'.freeze

  # O que a Receita confere ao salvar. Sem conta (o catálogo das receitas prontas), nada depende dela.
  def self.problemas_ao_salvar(conta, passo, account_user)
    return [] if conta.nil?

    id = passo['id']
    [*(frase(:lista_de_email_desligada, passo: id) unless ::EmailCampaigns::Config.enabled?),
     *(frase(:lista_de_email_sem_permissao, passo: id) if account_user && !account_user.permission_granted?(PERMISSAO)),
     *(frase(:lista_de_email_de_fora, passo: id, id: passo['lista_id']) unless EmailList.exists?(account_id: conta.id, id: passo['lista_id']))]
  end

  def self.frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  def initialize(execucao:, passo:, alvo:)
    @passo = passo
    @alvo = alvo
    @automacao = execucao.dona
    @conta = execucao.account
    @quem = @automacao.ligada_por
  end

  def executar
    return sem_acesso('quem_ligou_sem_permissao_lista') unless pode_mexer_na_lista?
    return pulado('lista_de_email_desligada') unless ::EmailCampaigns::Config.enabled?

    lista = EmailList.includes(:label).find_by(account_id: @conta.id, id: @passo['lista_id'])
    return pulado('lista_de_email_sumiu') if lista.nil?

    contato = ::Autonomia::Automacao::Contexto.de(@alvo).contato
    return pulado('sem_contato') if contato.nil?
    return sem_acesso('quem_ligou_sem_acesso') unless ::Autonomia::Automacao::Acesso.new(@automacao).alcanca?(contato)
    return pulado('lista_contato_sem_email', contato) if contato.email.blank?

    por_na_lista(lista, contato)
  end

  private

  def pode_mexer_na_lista?
    account_user = @quem && @conta.account_users.find_by(user_id: @quem.id)
    account_user.present? && account_user.permission_granted?(PERMISSAO)
  end

  def por_na_lista(lista, contato)
    titulo = lista.label.title
    posta = contato.with_lock do
      atuais = contato.label_list
      next false if atuais.any? { |atual| atual.casecmp?(titulo) }

      ::Autonomia::Automacao::Ato.da(@automacao.id) { contato.update_labels(atuais + [titulo]) }
      true
    end
    return pulado('ja_na_lista', contato) unless posta

    Resultado.new(tipo: :ok, motivo: nil, dados: { 'lista_id' => lista.id, 'contato_id' => contato.id })
  end

  def pulado(motivo, contato = nil)
    Resultado.new(tipo: :pulado, motivo: motivo, dados: contato ? { 'contato_id' => contato.id } : {})
  end

  def sem_acesso(motivo) = Resultado.new(tipo: :sem_acesso, motivo: motivo, dados: {})
end
