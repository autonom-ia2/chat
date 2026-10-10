# Multifunil (#1260): a IA de assunto nasce em Automática (2) e as caixas que estavam no padrão antigo, Desligada (0),
# passam para Automática. Decisão do Rodrigo em 10/10/2026: ligada para todas já no deploy. Em 10/10 nenhuma caixa
# tinha mudado o padrão, então Desligada era só o padrão, não uma escolha. Quem quiser desliga na caixa.
class TurnOnSubjectAiByDefault < ActiveRecord::Migration[7.2]
  def up
    change_column_default :crm_inbox_settings, :subject_ai_mode, from: 0, to: 2
    execute 'UPDATE crm_inbox_settings SET subject_ai_mode = 2, updated_at = NOW() WHERE subject_ai_mode = 0'
  end

  def down
    change_column_default :crm_inbox_settings, :subject_ai_mode, from: 2, to: 0
  end
end
