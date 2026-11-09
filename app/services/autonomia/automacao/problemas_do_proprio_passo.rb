# Os passos que se conferem sozinhos ao salvar, na própria classe (Receita#problemas_do_passo): o "Passar para a agente
# de IA" (G15), o "criar card" (G4), que confere também a pessoa, a campanha (G14), que confere o gatilho, a pessoa e a
# campanha da tela, a prospecção (G21, #2706), que confere o gatilho, a pessoa, a busca, a etapa e as etiquetas, e o
# "para cada item" (G24, #2771), que confere as flags, os campos, a etapa e a pessoa.
module Autonomia::Automacao::ProblemasDoProprioPasso
  TIPOS = %w[ia_assumir card campanha prospeccao para_cada].freeze

  module_function

  def de(passo, receita, conta:, account_user:)
    case passo['tipo']
    when 'card' then ::Autonomia::Automacao::PassoDeCard.problemas_ao_salvar(conta, passo, account_user)
    when 'para_cada' then ::Autonomia::Automacao::PassoParaCada.problemas_ao_salvar(conta, passo, account_user)
    when 'campanha' then ::Autonomia::Automacao::PassoDeCampanha.problemas_ao_salvar(passo, receita, conta: conta, account_user: account_user)
    when 'prospeccao'
      ::Autonomia::Automacao::PassoDeProspeccao.problemas_ao_salvar(passo, receita, conta: conta, account_user: account_user)
    else ::Autonomia::Automacao::PassoDeIaAssumir.problemas_ao_salvar(conta, passo)
    end
  end
end
