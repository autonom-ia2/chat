# #1433 F1a — o papel do agente na caixa (tabela do fork, nenhuma do Chatwoot):
# - porta: atende primeiro todas as conversas da caixa. Uma por caixa (índice único parcial).
# - area:  agente da equipe; recebe a conversa quando alguém passa. Só existe em caixa com porta ativa (validação do
#          model). Um agente tem no máximo um vínculo ativo por caixa (índice único do par).
# Todo vínculo existente vira porta: até aqui só existia a porta.
#
# Transacional (tabela de poucas linhas). Se o banco tiver caixa com dois vínculos ativos — o índice antigo impede isso,
# mas confere antes —, a migration para com a caixa e os vínculos na mensagem e nada muda (a transação desfaz tudo).
class AddPapelToAutonomiaAgentInboxes < ActiveRecord::Migration[7.2]
  INDICE_ANTIGO = 'idx_autonomia_agent_inboxes_on_live_inbox_uniq'.freeze
  INDICE_PORTA = 'idx_autonomia_agent_inboxes_on_live_porta_uniq'.freeze
  INDICE_PAR = 'idx_autonomia_agent_inboxes_on_live_inbox_agent_uniq'.freeze

  class VinculoDuplicado < StandardError; end
  class AreaAtiva < StandardError; end

  def up
    recusar_caixa_com_dois_vinculos!
    add_column :autonomia_agent_inboxes, :papel, :string, null: false, default: 'porta'
    add_index :autonomia_agent_inboxes, :inbox_id, unique: true, name: INDICE_PORTA, where: "papel = 'porta' AND deleted_at IS NULL"
    add_index :autonomia_agent_inboxes, [:inbox_id, :autonomia_agent_id], unique: true, name: INDICE_PAR, where: 'deleted_at IS NULL'
    remove_index :autonomia_agent_inboxes, name: INDICE_ANTIGO
  end

  # Voltar só é possível sem área ativa: o índice antigo aceita um vínculo ativo por caixa.
  def down
    recusar_area_ativa!
    add_index :autonomia_agent_inboxes, :inbox_id, unique: true, name: INDICE_ANTIGO, where: 'deleted_at IS NULL'
    remove_index :autonomia_agent_inboxes, name: INDICE_PAR
    remove_index :autonomia_agent_inboxes, name: INDICE_PORTA
    remove_column :autonomia_agent_inboxes, :papel
  end

  private

  def recusar_caixa_com_dois_vinculos!
    duplicadas = select_rows(<<~SQL.squish)
      SELECT inbox_id, string_agg(id::text, ',' ORDER BY id) FROM autonomia_agent_inboxes
      WHERE deleted_at IS NULL AND inbox_id IS NOT NULL GROUP BY inbox_id HAVING count(*) > 1
    SQL
    return if duplicadas.empty?

    detalhe = duplicadas.map { |inbox_id, ids| "caixa #{inbox_id}: vínculos #{ids}" }.join('; ')
    raise VinculoDuplicado, "autonomia_agent_inboxes tem mais de um vínculo ativo na mesma caixa (#{detalhe}). " \
                            'Escolha qual fica ativo antes de migrar; nada foi alterado.'
  end

  def recusar_area_ativa!
    ids = select_values("SELECT id FROM autonomia_agent_inboxes WHERE papel = 'area' AND deleted_at IS NULL ORDER BY id")
    return if ids.empty?

    raise AreaAtiva, "Há vínculo de área ativo (#{ids.join(', ')}). Solte-os com Autonomia::Agents::Areas.desvincular! " \
                     'antes de voltar; nada foi alterado.'
  end
end
