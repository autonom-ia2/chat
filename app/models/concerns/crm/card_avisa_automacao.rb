# Lote 4 da Automação livre (#2682): o card mudou num campo que a receita lê (Autonomia::Automacao::Valores, `card.*`), e
# o "esperar até" que espera nele confere a condição agora, em vez de no fim do prazo: o campo que o corretor preencheu,
# a etapa nova, o ganho. Depois do commit; o Despertador (`card_mudou`) loga o erro e nunca desfaz a edição. É o ponto único
# da Automação livre para "o card mudou", venha da tela, da API, da IA ou do lote.
#
# Na transação com várias gravações do mesmo card, o after_commit só vê em `saved_changes` a última. Por isso cada
# gravação anota, no after_save, o que mudou, junto com a transação (ou o savepoint) em que gravou; o after_commit junta
# as anotações e as limpa. Assim a 1ª gravação que mudou a etapa acorda, mesmo que a 2ª só tenha mexido em outra coluna.
# O rollback tira só as gravações da transação desfeita: o savepoint (`requires_new`) desfeito leva as dele, e as da
# transação de fora continuam valendo (#2750, revisão).
#
# O gatilho "card atualizado" (G27, #2661) nasce aqui também (Autonomia::Automacao::CardAtualizado): cada gravação soma
# o par [antes, agora] do valor e dos campos personalizados, e o commit vira um evento só, com o `antes` da 1ª gravação.
# O card criado também conta (tudo vindo do vazio); ele não acorda espera, só dispara o gatilho.
#
# Limite: só a escrita que passa pelos callbacks do modelo. `update_all` e `update_columns` não passam, como a soltura
# dos cards de quem saiu (Agents::DestroyJob, `owner_id`) e a anonimização (Crm::Cards::Anonimizador). Nesses casos
# ninguém acorda agora, e o "esperar até" confere no prazo, pela varredura do relógio.
module Crm::CardAvisaAutomacao
  extend ActiveSupport::Concern

  # As colunas por trás dos valores `card.*` (título, etapa, funil, situação, valor, responsável, time, motivo da perda
  # e os atributos). Mudança só de outra coluna (updated_at, contadores) não acorda ninguém.
  LIDAS_PELA_AUTOMACAO = %w[title stage_id pipeline_id status value_cents owner_id team_id lost_reason custom_attributes].freeze

  included do
    after_save :anotar_mudanca_lida
    after_commit :avisar_automacao_livre, on: %i[create update]
    after_rollback :esquecer_mudanca_lida
  end

  private

  # O card novo não tem quem espere nele, mas conta para o "card atualizado".
  def anotar_mudanca_lida
    gravacao = { transacao: self.class.connection.current_transaction.state, criado: previously_new_record?,
                 lida: !previously_new_record? && saved_changes.keys.intersect?(LIDAS_PELA_AUTOMACAO),
                 soma: ::Autonomia::Automacao::MudancaDoCard.somar(nil, saved_changes) }
    @gravacoes_do_card = [*@gravacoes_do_card, gravacao]
  end

  def avisar_automacao_livre
    gravacoes = gravacoes_valendo
    @gravacoes_do_card = nil
    soma = gravacoes.reduce({}) { |junta, gravacao| junta.merge(gravacao[:soma]) { |_chave, antes, agora| [antes.first, agora.last] } }
    ::Autonomia::Automacao::Despertador.card_mudou(self) if gravacoes.any? { |gravacao| gravacao[:lida] }
    ::Autonomia::Automacao::CardAtualizado.avisar(self, soma, criado: gravacoes.any? { |gravacao| gravacao[:criado] }) if soma.present?
  end

  # Só as gravações da transação desfeita saem (o estado do savepoint desfeito passa a `rolledback?`, e o da transação
  # de fora desfeita leva junto os de dentro).
  def esquecer_mudanca_lida
    @gravacoes_do_card = gravacoes_valendo.presence
  end

  def gravacoes_valendo = Array(@gravacoes_do_card).reject { |gravacao| gravacao[:transacao].rolledback? }
end
