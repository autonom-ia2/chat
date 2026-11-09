# Lote 4 da Automação livre (#2682): o card mudou num campo que a receita lê (Autonomia::Automacao::Valores, `card.*`), e
# o "esperar até" que espera nele confere a condição agora, em vez de no fim do prazo: o campo que o corretor preencheu,
# a etapa nova, o ganho. Depois do commit; o Despertador (`card_mudou`) loga o erro e nunca desfaz a edição. É o ponto único
# da Automação livre para "o card mudou", venha da tela, da API, da IA ou do lote.
#
# Na transação com várias gravações do mesmo card, o after_commit só vê em `saved_changes` a última. Por isso cada
# gravação anota, no after_save, se mudou uma coluna lida; o after_commit confere a anotação e a limpa (o rollback
# também limpa). Assim a 1ª gravação que mudou a etapa acorda, mesmo que a 2ª só tenha mexido em outra coluna.
#
# O gatilho "card atualizado" (G27, #2661) nasce aqui também (Autonomia::Automacao::CardAtualizado): cada gravação soma
# o par [antes, agora] do valor e dos campos personalizados, e o commit vira um evento só, com o `antes` da 1ª gravação.
# O card criado também conta (tudo vindo do vazio); ele não acorda espera, só dispara o gatilho.
#
# A troca de quem cuida do card (G9, #2707: o dono ou o time) também nasce aqui (Autonomia::Automacao::TrocaNoCard),
# somada do mesmo jeito, com o anterior da 1ª gravação. O card criado não é troca.
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
    @criado_na_transacao ||= previously_new_record?
    @mudancas_do_card = ::Autonomia::Automacao::MudancaDoCard.somar(@mudancas_do_card, saved_changes)
    @trocas_no_card = ::Autonomia::Automacao::TrocaNoCard.somar(@trocas_no_card, saved_changes) unless @criado_na_transacao
    return if previously_new_record? || !saved_changes.keys.intersect?(LIDAS_PELA_AUTOMACAO)

    @mudou_o_que_a_automacao_le = true
  end

  def avisar_automacao_livre
    mudou = @mudou_o_que_a_automacao_le
    soma = @mudancas_do_card
    criado = @criado_na_transacao
    trocas = @trocas_no_card
    esquecer_mudanca_lida
    ::Autonomia::Automacao::Despertador.card_mudou(self) if mudou
    ::Autonomia::Automacao::CardAtualizado.avisar(self, soma, criado: criado) if soma.present?
    ::Autonomia::Automacao::TrocaNoCard.avisar(self, trocas) if trocas.present?
  end

  def esquecer_mudanca_lida
    @mudou_o_que_a_automacao_le = nil
    @mudancas_do_card = nil
    @criado_na_transacao = nil
    @trocas_no_card = nil
  end
end
