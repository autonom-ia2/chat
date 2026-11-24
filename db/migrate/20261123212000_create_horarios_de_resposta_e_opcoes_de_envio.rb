# #3101 (F5 do épico #3095): melhor horário de cada cliente e reenvio a quem não respondeu. Duas tabelas novas do fork,
# vazias: sem trava em tabela que já existe, sem job enfileirado (o aprendizado e o reenvio rodam por cron).
#
# - horarios_de_resposta: a hora em que cada cliente costuma escrever, aprendida pelo
#   Autonomia::MelhorHorario::AprenderJob. `por_hora` são as 24 contagens das mensagens dele nos últimos 180 dias, no
#   fuso dele; `respostas`, o total; `hora`, a hora escolhida (nula enquanto não há o mínimo de mensagens). Uma linha
#   por contato.
# - campanha_opcoes_de_envio: as opções de envio de uma campanha da jornada, sem mexer nas tabelas de campanha
#   (construção aditiva). Uma linha por campanha (WhatsApp Oficial e SMS em `campaigns`, WhatsApp API, e-mail). Já leva
#   as colunas do reenvio (#3101, §4.3): quem recebe a segunda mensagem, quantos dias depois, a mensagem, a situação, a
#   hora em que sai e a campanha que ela gerou.
#
# Chaves: contato em cascata (apagar a pessoa apaga a hora dela); conta sem cascata, como as outras tabelas da conta: a
# exclusão da conta (Autonomia::ExclusaoDaConta) apaga as linhas antes do DELETE da conta. A campanha é polimórfica e
# não tem chave.
class CreateHorariosDeRespostaEOpcoesDeEnvio < ActiveRecord::Migration[7.2]
  def change
    criar_horarios_de_resposta
    criar_opcoes_de_envio
  end

  private

  # Sem timestamps: `calculado_em` é a única data que importa, e o job grava por cima a cada cálculo.
  def criar_horarios_de_resposta
    create_table :horarios_de_resposta do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.integer :por_hora, array: true, null: false
      t.integer :respostas, null: false, default: 0
      t.integer :hora, limit: 2
      t.datetime :calculado_em, null: false
      t.index %i[account_id contact_id], unique: true, name: 'idx_horarios_de_resposta_contato'
    end
  end

  def criar_opcoes_de_envio
    create_table :campanha_opcoes_de_envio do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'idx_campanha_opcoes_de_envio_conta' }
      t.string :campanha_type, null: false
      t.bigint :campanha_id, null: false
      t.boolean :melhor_horario, null: false, default: false
      t.string :reenvio_quem
      t.integer :reenvio_dias
      t.jsonb :reenvio_mensagem
      t.string :reenvio_status
      t.datetime :reenvio_em
      t.string :reenvio_campanha_type
      t.bigint :reenvio_campanha_id
      t.timestamps
      t.index %i[campanha_type campanha_id], unique: true, name: 'idx_campanha_opcoes_de_envio_campanha'
      t.index %i[reenvio_status reenvio_em], name: 'idx_campanha_opcoes_de_envio_reenvio'
    end
  end
end
