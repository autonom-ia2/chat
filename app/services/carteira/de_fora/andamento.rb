# A leitura do PDF de um seguro de outra corretora (E6.5, #2899), como a tela pergunta até ela terminar:
#   { leituraId:, estado: 'lendo' }
#   { leituraId:, estado: 'lido', lido: { tipo:, seguradora:, termina:, corretora: }, tambem: [...] }
#   { leituraId:, estado: 'recusado', recusa: 'nao_e_apolice' }
#   { leituraId:, estado: 'falhou', recusa: 'nao_deu_para_ler' }
# Lê o item só pelo Carteira::ItemLido (decisão D1).
#
# - `lido` são os campos que a pessoa confere e pode trocar antes de guardar: o tipo, a seguradora, quando termina e a
#   corretora em que o seguro está. O que o leitor não achou vem nulo ("não achei" nunca vira dado): a tela pede para a
#   pessoa escrever.
# - `tambem` é o resto do que foi lido (número, começo, valor e o bem), cada um `{ campo:, valor:, confira: }`. O achado com
#   certeza é guardado junto; o que está a confirmar (o valor escrito sem "R$") vem com `confira: true` e só é guardado
#   se a pessoa disser que está certo. O que não foi achado não aparece.
# O telefone e o e-mail achados no PDF não aparecem: não vão para o contato (decisão P5).
#
# A leitura é procurada só entre as de fora desta pessoa, na conta dela; a que não existe mais (guardada, ou que saiu na
# limpeza) responde `leitura_expirou`. O item que passou do tempo limite na fila conta como `falhou`.
class Carteira::DeFora::Andamento
  NAO_E_APOLICE = Carteira::Leitor::Resultado::NAO_E_APOLICE
  NAO_DEU = Carteira::Leitor::Resultado::NAO_DEU
  # campo da tela => nome do leitor
  DO_FORMULARIO = { 'tipo' => 'tipo', 'seguradora' => 'seguradora', 'termina' => 'fim_vigencia', 'corretora' => 'corretora' }.freeze
  TAMBEM = { 'numero' => 'numero', 'comeca' => 'inicio_vigencia', 'valor' => 'valor_centavos', 'bem' => 'bem' }.freeze

  def initialize(pessoa, leitura_id)
    @pessoa = pessoa
    @leitura_id = leitura_id
  end

  def call
    item = Carteira::DeFora.item_da(@pessoa, @leitura_id)
    raise CustomExceptions::CarteiraRecusa, 'leitura_expirou' unless item

    { leituraId: item.leitura_id }.merge(do_item(item))
  end

  private

  def do_item(item)
    case item.estado
    when 'lido' then { estado: 'lido' }.merge(lido(Carteira::ItemLido.new(item)))
    when 'recusado' then { estado: 'recusado', recusa: NAO_E_APOLICE }
    when 'lendo' then item.created_at < Carteira::LerItem::PRAZO.ago ? falhou : { estado: 'lendo' }
    else falhou
    end
  end

  def lido(lido)
    { lido: DO_FORMULARIO.transform_values { |nome| lido.certo(nome) },
      tambem: TAMBEM.filter_map { |campo, nome| do_resto(lido, campo, nome) } }
  end

  def do_resto(lido, campo, nome)
    return if lido.nao_achei?(nome)

    valor = lido.valor(nome)
    { campo: campo, valor: campo == Carteira::Campos::VALOR ? Carteira::Campos.em_reais(valor) : valor, confira: lido.a_confirmar?(nome) }
  end

  def falhou
    { estado: 'falhou', recusa: NAO_DEU }
  end
end
