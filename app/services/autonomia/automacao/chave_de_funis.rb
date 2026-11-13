# A receita pede a chave de funis (D2)? Saiu do AutomacoesController (#2933) para valer também nos blocos que ela usa.
#
# Passo de funil exige a chave de funis de quem salva e de quem liga: as mesmas CHAVES da regra do funil
# (crm_manage_pipelines ou crm_admin). O catálogo esconder o passo não autoriza nada: a API confere aqui. O gatilho de
# card (#2499) também pede a chave, e o retorno (G3), que cria pelo crm/follow_ups, e o "criar card" (G4). Ler o card a
# partir de uma conversa (#2716) também: no gatilho de conversa, `card.*` (a âncora do "em outro registro" inclusa) e
# `origem.card.*` no ramo (CardDaConversa.le?); em qualquer gatilho, o ramo que roda numa conversa e lê o card dela
# (EmOutroRegistro.de_funil?). Decisão 19 do Rodrigo (09/11).
#
# #2933: o bloco roda com a permissão de quem ligou a automação que o chama. Se um bloco alcançado (Bloco.conferir_cadeia,
# em profundidade, pelas versões ativas) pede a chave, a automação que o usa também pede.
module Autonomia::Automacao::ChaveDeFunis
  # Passos nativos de funil: o retorno (G3), que cria pelo crm/follow_ups, o "criar card" (G4), o "para cada item" (G24)
  # e a prospecção (G21), que cria card ao buscar.
  PASSOS_DE_FUNIL = %w[retorno card para_cada prospeccao].freeze

  module_function

  def precisa?(receita, conta, account_user)
    de_funil?(receita, conta, account_user) || blocos(receita, conta).any? do |bloco|
      de_funil?(bloco.versao_ativa&.receita.to_h, conta, account_user)
    end
  end

  def de_funil?(receita, conta, account_user)
    return true if ::Autonomia::Automacao::Gatilhos.do_card?(receita.dig('gatilho', 'tipo'))
    return true if de_conversa?(receita) && ::Autonomia::Automacao::CardDaConversa.le?(receita)

    ::Autonomia::Automacao::Receita.new(receita, conta: conta, account_user: account_user).passos.any? { |passo| passo_de_funil?(passo, receita) }
  end

  # O passo de funil, o "em outro registro" que lê cards (G18) ou cujo ramo numa conversa lê o card dela (#2716), a ação
  # de funil e o "para cada" nos cards de uma etapa (#2932).
  def passo_de_funil?(passo, receita)
    PASSOS_DE_FUNIL.include?(passo['tipo']) || ::Autonomia::Automacao::EmOutroRegistro.de_funil?(passo, receita) ||
      (passo['tipo'] == 'acao' && ::Autonomia::Automacao::AcoesPermitidas.de_funil?(passo['acao'])) ||
      (::Autonomia::Automacao::RepetirLista.do_tipo?(passo) && passo.dig('lista', 'de') == 'etapa')
  end

  # Só a conversa lê o card dela (#2716); no gatilho de contato, `card.*` é o valor_fora_do_alvo da Receita.
  def de_conversa?(receita) = ::Autonomia::Automacao::Gatilhos.alvo(receita.dig('gatilho', 'tipo')) == 'Conversation'

  # Os blocos que a receita alcança, sem repetir; o laço e o fundo a Receita recusa (PassoUsarBloco).
  def blocos(receita, conta)
    ids = ::Autonomia::Automacao::Bloco.usados(receita)
    return [] if ids.empty?

    ::Autonomia::Automacao::Definicao.where(account_id: conta.id, bloco: true, id: ids)
                                     .flat_map { |bloco| ::Autonomia::Automacao::Bloco.conferir_cadeia(bloco, conta).last }.uniq
  end
end
