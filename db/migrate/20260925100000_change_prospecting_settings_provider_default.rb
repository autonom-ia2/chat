# O GOOGLE PLACES VIRA O PROVIDER PADRÃO DA PROSPECÇÃO (chat#683, E0).
#
# A chave do Google passou a ser da plataforma, então conta nova já nasce buscando no Google. Só muda o default da
# coluna: a linha de quem já tem configuração fica como está (a troca das contas em `mock` é passo de produção, com
# rollback próprio). O `mock` continua aceito pelo model para desenvolvimento e teste.
class ChangeProspectingSettingsProviderDefault < ActiveRecord::Migration[7.2]
  def change
    change_column_default :autonomia_prospecting_settings, :provider, from: 'mock', to: 'google_places'
  end
end
