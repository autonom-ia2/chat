# Convite de reunião no e-mail (#2042): a versão anterior do mesmo convite (ConversaCanal::ConviteSubstituido) é achada
# pela chave do UID em `additional_attributes.convite_uid_sha256`, por índice, sem varrer o texto das mensagens.
# - Índice parcial (só as mensagens com convite) e concorrente: não trava a escrita em `messages`. Se uma rodada
#   anterior caiu no meio do CREATE INDEX CONCURRENTLY, o índice inválido é refeito.
# - Preenche a chave nos convites já recebidos (o cartão entrou em 20/10/2026; antes disso nenhum e-mail tem convite).
#   Poucas mensagens: lidas de uma vez pelo índice de created_at, sem percorrer a tabela pelo id. Em produção o
#   content_attributes vem guardado como JSON em texto; lido duas vezes quando preciso. O UPDATE só junta a chave
#   onde falta, sem regravar o resto de additional_attributes.
# - Rodar de novo não muda nada. O down tira só o índice; a chave gravada fica, e o código anterior a ignora.
class AddConviteUidIndexToMessages < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'index_messages_on_convite_uid_sha256'.freeze
  DESDE = Time.utc(2026, 10, 20)

  Mensagem = Class.new(ActiveRecord::Base) do
    self.table_name = 'messages'
  end

  def up
    remove_index :messages, name: INDICE, algorithm: :concurrently if indice_invalido?
    add_index :messages, "(additional_attributes ->> 'convite_uid_sha256')", name: INDICE,
                                                                             where: "(additional_attributes ->> 'convite_uid_sha256') IS NOT NULL",
                                                                             algorithm: :concurrently, if_not_exists: true
    preencher
  end

  def down
    remove_index :messages, name: INDICE, algorithm: :concurrently, if_exists: true
  end

  private

  def indice_invalido?
    select_value("SELECT NOT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = '#{INDICE}'") == true
  end

  def preencher
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

  def convite_uid(valor)
    valor = JSON.parse(valor) while valor.is_a?(String)
    valor.to_h.dig('email', 'convite', 'uid')
  rescue JSON::ParserError, TypeError
    nil
  end
end
