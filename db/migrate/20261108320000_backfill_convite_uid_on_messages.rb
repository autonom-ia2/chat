# Convite de reunião no e-mail (#2042): grava a chave do UID (`additional_attributes.convite_uid_sha256`) nos convites
# recebidos antes do código que a grava na chegada. O cartão entrou em 20/10/2026; antes disso nenhum e-mail tem convite.
# - Poucas linhas (21/10/2026: 0 na hub2you, até 4 na financial), lidas pelo índice de created_at, sem percorrer a tabela
#   pelo id; por isso sem lotes.
# - Em produção o content_attributes vem guardado como JSON em texto; lido duas vezes quando preciso.
# - O UPDATE só junta a chave onde ela falta, sem regravar o resto de additional_attributes. Rodar de novo não muda nada.
# - O down não desfaz: a chave a mais é inofensiva.
class BackfillConviteUidOnMessages < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  DESDE = Time.utc(2026, 10, 20)

  Mensagem = Class.new(ActiveRecord::Base) do
    self.table_name = 'messages'
  end

  def up
    convites = Mensagem.where(message_type: 0, created_at: DESDE..).where("content_attributes::text LIKE '%convite%'")
    convites.pluck(:id, :content_attributes).each do |id, conteudo|
      uid = convite_uid(conteudo)
      next if uid.blank?

      Mensagem.where(id: id).where("(additional_attributes ->> 'convite_uid_sha256') IS NULL").update_all( # rubocop:disable Rails/SkipsModelValidations
        ["additional_attributes = COALESCE(additional_attributes, '{}'::jsonb) || jsonb_build_object('convite_uid_sha256', ?::text)",
         Digest::SHA256.hexdigest(uid.to_s)]
      )
    end
  end

  def down; end

  private

  def convite_uid(valor)
    valor = JSON.parse(valor) while valor.is_a?(String)
    valor.to_h.dig('email', 'convite', 'uid')
  rescue JSON::ParserError, TypeError
    nil
  end
end
