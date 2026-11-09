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

  # O que a ação `acao` criou, pelo caderno: `{ 'tipo', 'id' }`, ou nil.
  def do_caderno(acao, caderno)
    tipo = ACOES[acao.to_s]
    id = tipo && caderno.mudancas.where(operacao: 'create', record_type: tipo).pick(:record_id)
    { 'tipo' => tipo, 'id' => id } if id
  end

  # O `{ 'tipo', 'id' }` que o passo `passo_id` criou nesta execução (o último, se ele rodou mais de uma vez), ou nil.
  def da_execucao(execucao, passo_id)
    return unless execucao

    execucao.registros.where(passo: passo_id.to_s, resultado: 'ok').where("dados ? 'criado'").reorder(id: :desc).pick(:dados)&.dig('criado')
  end

  # O registro criado, sempre na conta da execução; nil se ele já não existe.
  def registro(execucao, passo_id)
    criado = da_execucao(execucao, passo_id).to_h
    escopo = { CONTATO => execucao&.account&.contacts, CARD => execucao&.account&.crm_cards }[criado['tipo']]
    escopo&.find_by(id: criado['id'])
  end
end
