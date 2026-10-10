# Multifunil 5/11 (#1145): a IA identifica o assunto da conversa.
# - crm_pipelines.when_to_use: o "Quando usar" do funil, o texto que a IA lê para escolher funil e assunto.
# - crm_inbox_settings.subject_ai_mode: o que a IA faz na caixa. 0 = desligada (padrão: nada muda para quem não ligar),
#   1 = sugerir, 2 = automática.
class AddSubjectAiToCrm < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_pipelines, :when_to_use, :text
    add_column :crm_inbox_settings, :subject_ai_mode, :integer, default: 0, null: false
  end
end
