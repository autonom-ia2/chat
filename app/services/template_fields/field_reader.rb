# O jeito comum de um resolvedor do catálogo (#1331) dizer o que sabe: `READERS` liga cada chave ao método que lê o
# valor. `keys` são as chaves que ele oferece; `value(key)` é o texto pronto ou nil (sem valor, ou chave de outro).
module TemplateFields::FieldReader
  def keys
    self.class::READERS.keys
  end

  def value(key)
    reader = self.class::READERS[key.to_s]
    reader && send(reader).to_s.squish.presence
  end
end
