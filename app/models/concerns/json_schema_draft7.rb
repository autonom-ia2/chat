# Abre um esquema JSON da plataforma do jeito que ele foi escrito: draft 7, com expressões ECMA.
#
# O json_schemer 2 (que a gem `mcp` exige) lê esquema sem `$schema` como draft 2020-12 e expressões
# como Ruby. No 2020-12, `items: [a, b]` deixa de conferir posição por posição; no Ruby, `^…$` casa
# com uma linha só de um texto de várias linhas. O 0.2, para o qual todos estes esquemas foram
# escritos, lia draft 7 e ECMA. Todo esquema da plataforma passa por aqui; só o MCP usa a gem direto.
module JsonSchemaDraft7
  module_function

  def schema(esquema, **opcoes)
    JSONSchemer.schema(esquema, meta_schema: JSONSchemer.draft7, regexp_resolver: 'ecma', **opcoes)
  end
end
