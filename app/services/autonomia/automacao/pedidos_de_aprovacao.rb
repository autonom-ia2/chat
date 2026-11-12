# Os pedidos do passo "Pedir aprovação" (#2931) do lado de quem aprova: a tela "Pedidos de aprovação" e o sino. O pedido
# é o registro do passo na espera (EsperaDeResposta, motivo `esperando_resposta`) com `para` (quem pode responder), `ate`
# (o prazo) e, depois, `decisao` ou `fechado`.
#
# Quem vê e responde: só quem está em `para` E ainda alcança o registro agora (ve_o_alvo?: o card pela CardPolicy, a
# conversa pela ConversationPolicy, a contato pela ContactPolicy), sempre dentro da conta. Quem perdeu o acesso depois
# do pedido não vê mais nem responde. Não pede a chave de automações: quem aprova é a equipe, não quem monta.
#
# A resposta é uma gravação só, condicionada: o pedido sem decisão e sem fechar, a execução aberta e o prazo por vencer.
# Dois cliques ao mesmo tempo: o primeiro vence, o segundo recebe "já respondido". A resposta que chega junto com o prazo
# também: o motor fecha o pedido (`fechar`) com a mesma condição antes de seguir pelo "ninguém respondeu".
module Autonomia::Automacao::PedidosDeAprovacao
  ESPERANDO = ::Autonomia::Automacao::EsperaDeResposta::ESPERANDO
  MAX_MOTIVO = 500
  # Contra defeito, não contra uso: os pedidos abertos de uma pessoa cabem numa tela.
  LIMITE = 100
  EXECUCAO_ABERTA = 'EXISTS (SELECT 1 FROM autonomia_automacao_execucoes execucao ' \
                    'WHERE execucao.id = autonomia_automacao_registros.execucao_id AND execucao.finalizada_em IS NULL)'.freeze
  SEM_DECISAO = "dados -> 'decisao' IS NULL AND dados -> 'fechado' IS NULL".freeze

  module_function

  # `account_user`: a pessoa na conta, já lida (a lista confere vários pedidos da mesma pessoa com uma leitura só).
  def ve_o_alvo?(pessoa, alvo, account_user = membro(pessoa, alvo))
    politica = politica_de(alvo)
    return false unless politica && da_mesma_conta?(pessoa, alvo, account_user)

    politica.new({ user: pessoa, account: alvo.account, account_user: account_user }, alvo).show?
  end

  def da_mesma_conta?(pessoa, alvo, account_user)
    pessoa.present? && account_user&.user_id == pessoa.id && alvo.account_id == account_user.account_id
  end

  def politica_de(alvo)
    case alvo
    when ::Crm::Card then ::Crm::CardPolicy
    when ::Conversation then ConversationPolicy
    when ::Contact then ContactPolicy
    end
  end

  # A pessoa na conta do registro (nil fora dela).
  def membro(pessoa, alvo) = (alvo.account.account_users.find_by(user_id: pessoa.id) if pessoa && alvo&.account)

  # Os pedidos de `pessoa` nesta conta, sem filtrar o alcance (quem chama confere com ve_o_alvo?). O índice parcial
  # idx_autonomia_automacao_registros_esperando (conta e data, só os registros de espera) responde a consulta sem ler os
  # outros registros da conta.
  def da_pessoa(conta, pessoa)
    ::Autonomia::Automacao::Registro.where(account_id: conta.id, motivo: ESPERANDO)
                                    .where("dados -> 'para' @> ?::jsonb", [pessoa.id].to_json)
                                    .includes(execucao: %i[versao automacao alvo])
  end

  # Os abertos que a pessoa ainda pode responder, do prazo mais perto ao mais longe.
  def abertos(conta, pessoa)
    account_user = conta.account_users.find_by(user_id: pessoa.id)
    return [] unless account_user

    escopo = da_pessoa(conta, pessoa).where(SEM_DECISAO).where(EXECUCAO_ABERTA)
    escopo.order(created_at: :desc).limit(LIMITE).to_a
          .select { |pedido| aberto?(pedido) && ve_o_alvo?(pessoa, pedido.execucao.alvo, account_user) }
          .sort_by { |pedido| pedido.dados['ate'].to_s }
  end

  # Um pedido de `pessoa`, aberto ou já respondido; nil quando não é dela ou ela não vê mais o registro.
  def da_pessoa_por_id(conta, pessoa, id)
    pedido = da_pessoa(conta, pessoa).find_by(id: id)
    pedido if pedido && ve_o_alvo?(pessoa, pedido.execucao.alvo)
  end

  def aberto?(pedido)
    dados = pedido.dados
    dados['decisao'].nil? && dados['fechado'].nil? && pedido.execucao.finalizada_em.nil? && prazo(pedido)&.future?
  end

  def prazo(pedido) = (Time.zone.parse(pedido.dados['ate'].to_s) if pedido.dados['ate'].present?)

  # :ok, :ja_respondido (decidido, fechado, execução terminada) ou :fora_do_prazo.
  def responder!(pedido, pessoa, aprovado:, motivo: nil)
    return :fora_do_prazo unless prazo(pedido)&.future?

    decisao = { 'aprovado' => aprovado == true, 'por' => pessoa.id, 'por_nome' => pessoa.name, 'em' => Time.current.iso8601,
                'motivo' => (motivo.to_s.squish.first(MAX_MOTIVO).presence unless aprovado) }.compact
    return :ja_respondido unless gravar(pedido, { 'decisao' => decisao })

    acordar(pedido)
    :ok
  end

  # O motor, no prazo: fecha o pedido que ninguém respondeu. Devolve se fechou.
  def fechar(pedido) = gravar(pedido, { 'fechado' => true }, aberta: false)

  def gravar(pedido, novo, aberta: true)
    escopo = ::Autonomia::Automacao::Registro.where(id: pedido.id).where(SEM_DECISAO)
    escopo = escopo.where(EXECUCAO_ABERTA) if aberta
    escopo.update_all(['dados = dados || ?::jsonb', novo.to_json]) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  # A mesma reserva da Escuta: a execução que espera neste passo anda agora, em vez de esperar o prazo.
  def acordar(pedido)
    execucao = ::Autonomia::Automacao::Execucao.find_by(id: pedido.execucao_id, estado: 'esperando')
    ::Autonomia::Automacao::Escuta.reservar(execucao) if execucao && execucao.cursor == pedido.passo
  end
end
