# #3106 (revisão do Codex) — ligar uma automação que já está gravada com ação que sai da plataforma (mandar mensagem,
# e-mail, webhook; o retorno que manda mensagem sozinho) faz ela agir sozinha dali em diante, e o desfazer não recolhe
# o que ela mandou. O nó `x-sem-volta` do esquema só via o corpo do pedido; com `{active: true}` sem as ações, as
# gravadas passavam sem confirmação. Aqui elas são conferidas pelo mesmo esquema, como se viessem no corpo.
#
# Só a passagem de desligada para ligada conta: renomear uma automação que já estava ligada segue com desfazer.
module Autonomia::Guide::LigaComEnvio
  REGRAS = ['PATCH automation_rules/:id', 'PUT automation_rules/:id'].freeze
  ETAPAS = ['PATCH crm/stage_automations/:id', 'PUT crm/stage_automations/:id'].freeze

  module_function

  # `dados` com o corpo já como a plataforma vai recebê-lo (`SemVolta.pelo_que_faz?` normaliza antes).
  def liga?(account, acao, dados)
    return false unless dados && (REGRAS + ETAPAS).include?(acao)

    regra = REGRAS.include?(acao)
    ligar, lista = regra ? %w[active actions] : %w[enabled steps]
    return false unless liga_sem_a_lista?(::Autonomia::Guide::Formatos::Conferencia.new(acao, dados[:corpo], conta: account).valores, ligar, lista)

    gravada = gravada(account, regra, (dados[:caminho] || {}).to_h.with_indifferent_access[:id])
    gravada.present? && ::Autonomia::Guide::Formatos::Conferencia.new(acao, { lista => gravada }, conta: account).sem_volta?
  end

  # O pedido liga e não traz as ações (as que vierem, o esquema já confere no corpo).
  def liga_sem_a_lista?(corpo, ligar, lista)
    ActiveModel::Type::Boolean.new.cast(corpo[ligar]) == true && corpo[lista].blank?
  end

  # As ações da automação desligada; nil quando ela não existe ou já estava ligada.
  def gravada(account, regra, id)
    if regra
      automacao = account.automation_rules.find_by(id: id)
      automacao.actions unless automacao.nil? || automacao.active?
    else
      automacao = account.crm_stage_automations.find_by(id: id)
      automacao.steps.map { |passo| passo.attributes.slice('action_type', 'action_config') } unless automacao.nil? || automacao.enabled?
    end
  end
end
