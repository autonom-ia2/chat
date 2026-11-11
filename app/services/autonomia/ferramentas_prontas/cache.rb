# O CACHE DAS FERRAMENTAS PRONTAS (#2858, F0). É da fonte, não da conta: o dado é público e igual para todas (o mesmo
# CEP tem o mesmo endereço). O que entra:
#   - a resposta encontrada, pela validade da consulta (`Consulta#validade`);
#   - o "não encontrado", por pouco tempo (`VALIDADE_DO_NAO_ENCONTRADO`), para o mesmo CEP inexistente repetido não gastar
#     a cota das fontes de novo.
# A falha nunca entra: a consulta seguinte tenta a fonte. A consulta sem validade (`nil`: o CPF, que é dado pessoal e
# calculado aqui) não passa pelo cache.
#
# A chave leva um HMAC dos parâmetros com segredo da plataforma: quem lê o Redis não reverte o CEP ou o CNPJ por força
# bruta. O filtro local (`Parametro#local?`) não entra na chave: a lista guardada é a da fonte, e o filtro roda depois.
# O cache fora do ar é só um cache a menos: a leitura vira "não tem", a escrita é pulada, e a consulta segue.
class Autonomia::FerramentasProntas::Cache
  # Sobe quando muda o formato do que a fonte guarda (o que é montado antes do cache): a resposta antiga não chega ao
  # agente sem o campo novo. v2 (#2906): o `nome` dos CEPs da rua e o formato novo dos hospitais.
  VERSAO = 'v2'.freeze
  VALIDADE_DO_NAO_ENCONTRADO = 1.hour
  NAO_ENCONTRADO = 'nao_encontrado'.freeze
  ENCONTRADO = 'encontrado'.freeze

  def initialize(fonte, consulta, params)
    @fonte = fonte
    @consulta = consulta
    @params = params
  end

  # -> { 'situacao' => 'encontrado', 'dados' => … }, { 'situacao' => 'nao_encontrado' } ou nil.
  def ler
    return if @consulta.validade.nil?

    Rails.cache.read(chave)
  rescue StandardError => e
    avisar('leitura', e)
    nil
  end

  # `validade`: a do provedor que respondeu, quando ele declara a sua (a reserva incompleta fica pouco ou nada); senão,
  # a da consulta.
  def encontrado(dados, validade: nil)
    tempo = validade || @consulta.validade
    gravar({ 'situacao' => ENCONTRADO, 'dados' => dados }, tempo) if tempo.nil? || tempo.positive?
  end

  def nao_encontrado
    gravar({ 'situacao' => NAO_ENCONTRADO }, VALIDADE_DO_NAO_ENCONTRADO)
  end

  def chave
    resumo = OpenSSL::HMAC.hexdigest('SHA256', self.class.segredo, @consulta.chave_do_cache(@params).to_json)
    "autonomia:prontas:#{VERSAO}:#{@fonte.chave}:#{@consulta.nome}:#{resumo}"
  end

  def self.segredo
    @segredo ||= Rails.application.key_generator.generate_key('autonomia/ferramentas_prontas/cache', 32)
  end

  private

  def gravar(valor, validade)
    return if @consulta.validade.nil?

    Rails.cache.write(chave, valor, expires_in: validade)
  rescue StandardError => e
    avisar('escrita', e)
  end

  def avisar(onde, erro)
    Rails.logger.warn("[autonomia][pronta] cache #{onde} falhou fonte=#{@fonte.chave} #{erro.class}")
  end
end
