# Os números do Conferir de uma busca no conector (E7, #2900), calculados no job (Carteira::Conector::Conferir#calcular!),
# nunca na requisição: a pessoa de cada registro é procurada sem criar ninguém (Carteira::Conector::PessoaDoRegistro#achar),
# uma vez por referência e documento. Devolve só contagens ({ 'seguros' => 3, ..., 'tipo_auto' => 2 }), que é o que
# `totais` guarda. O que cada número quer dizer está em Carteira::Conector::Conferir.
class Carteira::Conector::Conferir::Contagem
  def initialize(leitura)
    @leitura = leitura
    @pessoas = Carteira::Conector::PessoaDoRegistro.new(leitura.account)
  end

  def call
    prontas = vistas.select { |vista| vista[:pronto] }
    seguros = prontas.uniq { |vista| vista[:ref] }
    { 'seguros' => seguros.size, 'ja_na_carteira' => seguros.count { |vista| vista[:dono]&.ja_na_carteira },
      'nao_deu' => falharam + (vistas.size - prontas.size), 'repetidos' => prontas.size - seguros.size, 'prontos' => prontas.size,
      **das_pessoas(prontas), **por_tipo(prontas) }
  end

  private

  def das_pessoas(prontas)
    pessoas = prontas.uniq { |vista| vista[:chave] }
    { 'pessoas' => pessoas.size, 'pessoas_novas' => pessoas.count { |vista| vista[:dono].nil? },
      'sem_telefone' => pessoas.count { |vista| vista[:dono].nil? || vista[:dono].pessoa.phone_number.blank? } }
  end

  # O tipo de cada seguro, pelo último registro dele (o endosso mais novo).
  def por_tipo(prontas)
    tipos = prontas.reverse.uniq { |vista| vista[:ref] }.map { |vista| vista[:lido].certo('tipo') || Carteira::Conector::TiposDoRamo::OUTRO }
    tipos.tally.transform_keys { |tipo| "tipo_#{tipo}" }
  end

  def falharam
    @leitura.itens.where(estado: Carteira::Conector::Ler::FALHOU).count
  end

  def vistas
    @vistas ||= begin
      donos = {}
      @leitura.itens.where(estado: Carteira::Conector::Ler::LIDO).order(:posicao).map { |item| vista(Carteira::ItemLido.new(item), donos) }
    end
  end

  # A pessoa de cada registro, sem criar ninguém: a mesma referência ou o mesmo documento é perguntado uma vez só.
  def vista(lido, donos)
    chave_de_busca = [lido.valor('ref'), lido.certo('segurado_documento')]
    dono = donos.fetch(chave_de_busca) { donos[chave_de_busca] = @pessoas.achar(lido) }
    { lido: lido, ref: lido.valor('ref'), dono: dono, pronto: dono.present? || @pessoas.nasce?(lido),
      chave: dono ? "pessoa:#{dono.pessoa.id}" : "nova:#{lido.certo('segurado_documento')}" }
  end
end
