# G9 (#2707): a troca de quem cuida do card, como gatilho. Dois gatilhos: `card.responsavel_mudou` (o dono, `owner_id`)
# e `card.time_mudou` (o time, `team_id`, a troca de time que a F8 promete).
#
# De onde vem: o próprio card, pelo gancho único da Automação livre (Crm::CardAvisaAutomacao), o mesmo do "card
# atualizado" (G27) e do Despertador. A troca chega por pelo menos seis caminhos (a tela, o upsert, a Lista do CRM em
# lote, o vínculo com a conversa, a etapa que atribui, a saída da triagem) e nem todos gravam atividade; a Lista do CRM
# grava só o dono novo. Cada gravação soma o par [antes, agora] (`somar`, no after_save) e o commit vira um evento só,
# com o `antes` da 1ª gravação: trocar e desfazer na mesma transação não é troca. O card que nasce não é troca.
#
# A marca leva o anterior: `card.responsavel_mudou:<card>:<anterior ou 0>:<updated_at µs>`. Os passos, dias depois,
# leem quem cuidava antes pela marca da execução; o filtro do gatilho, pela marca da partida (Contexto#evento). A mesma
# troca entregue duas vezes tem a mesma marca (índice único automacao_id + evento); a volta é outro fato.
#
# Os valores (só nesses gatilhos; o salvar recusa no resto, `troca_so_no_gatilho`): quem cuidava antes (id, nome e se
# está ausente agora, G23) e o time de antes (id e nome). A pessoa e o time são achados na conta do alvo, nunca só pelo
# id da marca: quem saiu da conta lê vazio.
module Autonomia::Automacao::TrocaNoCard
  RESPONSAVEL = 'card.responsavel_mudou'.freeze
  TIME = 'card.time_mudou'.freeze
  TIPOS = { 'owner_id' => RESPONSAVEL, 'team_id' => TIME }.freeze

  VALORES = {
    'gatilho.responsavel_anterior_id' => ->(contexto) { pessoa_anterior(contexto)&.user_id },
    'gatilho.responsavel_anterior_nome' => ->(contexto) { pessoa_anterior(contexto)&.user&.name },
    'gatilho.responsavel_anterior_ausente' => lambda do |contexto|
      pessoa = pessoa_anterior(contexto)
      pessoa.present? && ::AccountUser.ausente_na_conta?(pessoa.account_id, pessoa.user_id)
    end,
    'gatilho.time_anterior_id' => ->(contexto) { time_anterior(contexto)&.id },
    'gatilho.time_anterior_nome' => ->(contexto) { time_anterior(contexto)&.name }
  }.freeze

  # O gatilho em que cada valor existe.
  DO_GATILHO = VALORES.keys.index_with { |caminho| caminho.start_with?('gatilho.time') ? TIME : RESPONSAVEL }.freeze

  FECHADOS = { 'gatilho.responsavel_anterior_ausente' => { 'opcoes' => [true, false], 'operadores' => %w[igual diferente] } }.freeze

  module_function

  # No after_save do card: a soma das trocas da transação, com o `antes` da 1ª gravação e o `agora` da última.
  def somar(acumulado, saved_changes)
    TIPOS.keys.select { |coluna| saved_changes.key?(coluna) }.each_with_object(acumulado.to_h.dup) do |coluna, soma|
      antes, agora = saved_changes[coluna]
      soma[coluna] = [soma.key?(coluna) ? soma[coluna].first : antes, agora]
    end
  end

  # No after_commit: cada troca de fato vira um evento, só com automação assinante na conta e no funil do card. O erro é
  # logado e nunca desfaz a edição.
  def avisar(card, soma)
    soma.to_h.each do |coluna, (antes, agora)|
      next if antes == agora

      tipo = TIPOS.fetch(coluna)
      dados = { pipeline_id: card.pipeline_id }
      next unless escuta.assinante?(card.account, tipo, dados, card_id: card.id)

      escuta.enfileirar_evento_do_card({ account_id: card.account_id, card_id: card.id, changed_attributes: dados,
                                         marca: marca(tipo, card, antes) }, tipo)
    end
  rescue StandardError => e
    escuta.registrar_erro("troca no card não enfileirou Crm::Card=#{card&.id}", e)
  end

  def marca(tipo, card, anterior_id) = "#{tipo}:#{card.id}:#{anterior_id.to_i}:#{card.updated_at.utc.iso8601(6)}"

  # O id de antes numa marca de troca do `tipo`; nil em outra marca ou quando não havia ninguém.
  def anterior_da_marca(marca, tipo)
    de, _card, anterior = marca.to_s.split(':', 4)
    id = Integer(anterior.to_s, 10, exception: false)
    id if de == tipo && id&.positive?
  end

  def do_gatilho?(caminho) = DO_GATILHO.key?(caminho.to_s)

  def pessoa_anterior(contexto)
    id = anterior_da_marca(contexto.evento, RESPONSAVEL)
    id && ::AccountUser.find_by(account_id: contexto.conta_id, user_id: id)
  end

  def time_anterior(contexto)
    id = anterior_da_marca(contexto.evento, TIME)
    id && ::Team.find_by(account_id: contexto.conta_id, id: id)
  end

  def escuta = ::Autonomia::Automacao::Escuta
end
