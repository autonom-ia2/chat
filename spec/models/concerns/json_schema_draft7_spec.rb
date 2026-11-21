require 'rails_helper'

# The platform schemas were written for json_schemer 0.2 (draft 7, ECMA patterns). The `mcp` gem needs
# json_schemer 2, whose defaults are draft 2020-12 and Ruby patterns; these are the two differences that bite.
RSpec.describe JsonSchemaDraft7 do
  it 'checks each position of a tuple items list, as draft 7 does' do
    schema = described_class.schema({ 'type' => 'array', 'items' => [{ 'type' => 'string' }, { 'type' => 'integer' }] })

    expect(schema.valid?(['a', 1])).to be(true)
    expect(schema.valid?([1, 'a'])).to be(false)
  end

  it 'anchors a pattern to the whole text, not to one line' do
    schema = described_class.schema({ 'type' => 'string', 'pattern' => '^[0-9]+$' })

    expect(schema.valid?('123')).to be(true)
    expect(schema.valid?("123\nnot a number")).to be(false)
  end

  it 'keeps the platform formats' do
    schema = described_class.schema({ 'type' => 'string', 'format' => JsonSchemaFormatos::LISTA_DE_EMAILS },
                                    formats: JsonSchemaFormatos::TODOS)

    expect(schema.valid?('a@b.com, c@d.com')).to be(true)
    expect(schema.valid?('não é e-mail')).to be(false)
  end
end
