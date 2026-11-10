# G49: o registro que um passo criou nesta execução vira valor (`criado.<id do passo>`, o id dele) e alvo dos passos
# seguintes. Exemplo 11, passo 3: o `POST contacts` cria o João; o "criar card" (G4) abre o card dele no quadro
# "Indicações" (`contato: {"$valor": "criado.<passo>"}`); a ação grava "indicado por Maria" no card que o passo criou;
# e o "em outro registro" (G18, ligação `criado_no_passo`) manda a mensagem ao João no card dele.
#
# Os passos que criam registro são uma lista fechada: o "criar card" e as ações que criam contato. O id sai do que o
# passo gravou, nunca da resposta: o caderno do Guia (Mudanca) anota cada linha criada, com o tipo, e a resposta do
# `POST contacts` nem traz o id no lugar em que o Guia procura. O registro do passo leva `criado: {tipo, id}`.
#
# Vale só na execução que criou (como o texto da IA, `ia.<passo>`): a filha do "em outro registro" não lê o que a mãe
# criou, nem a mãe o da filha. Antes do passo rodar, ou no caminho em que ele não rodou (ou pulou), lê vazio, e o passo
# que lê pula com `faltou_valor`. Quem age no registro é sempre quem ligou: a ação passa pela política do endpoint, o
# "criar card" e a filha conferem o alcance (Acesso#alcanca?).
module Autonomia::Automacao::RegistroCriado
  PREFIXO = 'criado.'.freeze
  CONTATO = 'Contact'.freeze
  CARD = 'Crm::Card'.freeze
  # As ações que criam registro e o tipo dele.
  ACOES = { 'POST contacts' => CONTATO, 'POST crm/cards/:card_id/contact' => CONTATO }.freeze

  module_function

  def caminho?(caminho) = caminho.to_s.start_with?(PREFIXO) && caminho.to_s.length > PREFIXO.length

  # "criado.p3" => "p3".
  def passo_do(caminho) = caminho.to_s.delete_prefix(PREFIXO)

  # O tipo do registro que o passo cria ('Contact', 'Crm::Card'), ou nil quando ele não cria.
  def tipo_do_passo(passo)
    return CARD if passo&.dig('tipo') == 'card'

    ACOES[passo['acao']] if passo&.dig('tipo') == 'acao'
  end

  # O que a ação `acao` criou, pelo caderno: `{ 'tipo', 'id' }`, ou nil. Se a ação criou mais de um registro do tipo
  # (o pedido que cria o contato e um contato ligado a ele), vale o primeiro criado, na ordem do caderno.
  def do_caderno(acao, caderno)
    tipo = ACOES[acao.to_s]
    id = tipo && caderno.mudancas.where(operacao: 'create', record_type: tipo).reorder(:id).pick(:record_id)
    { 'tipo' => tipo, 'id' => id } if id
  end

  # O `{ 'tipo', 'id' }` que o passo `passo_id` criou nesta execução, ou nil. Vale a ÚLTIMA passagem do passo (o laço que
  # repete passos, #2791, passa por ele mais de uma vez): se ela pulou, falhou ou não criou nada, lê vazio, nunca o id
  # de uma passagem anterior.
  def da_execucao(execucao, passo_id)
    return unless execucao

    ultima = execucao.registros.where(passo: passo_id.to_s).reorder(id: :desc).first
    ultima.dados.to_h['criado'] if ultima&.resultado == 'ok'
  end

  # O registro criado, sempre na conta da execução; nil se ele já não existe.
  def registro(execucao, passo_id)
    criado = da_execucao(execucao, passo_id).to_h
    escopo = { CONTATO => execucao&.account&.contacts, CARD => execucao&.account&.crm_cards }[criado['tipo']]
    escopo&.find_by(id: criado['id'])
  end
end
