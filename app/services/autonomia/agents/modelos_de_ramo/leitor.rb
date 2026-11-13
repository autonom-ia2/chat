# Lê os modelos prontos de uma pasta (#2881): um `<chave>.yml` e um `<chave>.md` por modelo. O que não abre, não é YAML
# ou não passa no `Formato` fica de fora, com o motivo no log (nome de campo e chave; nunca o conteúdo): o Construtor
# segue funcionando, só sem aquele modelo.
class Autonomia::Agents::ModelosDeRamo::Leitor
  LOG_TAG = '[Autonomia::Agents::ModelosDeRamo]'.freeze

  def initialize(pasta)
    @pasta = Pathname(pasta)
  end

  # chave => Modelo, na ordem do nome do arquivo (o `Dir.glob` já devolve em ordem).
  def modelos
    Dir.glob(@pasta.join('*.yml').to_s).filter_map { |arquivo| ler(File.basename(arquivo, '.yml')) }.index_by(&:chave).freeze
  end

  private

  def ler(chave)
    dados = YAML.safe_load(File.read(@pasta.join("#{chave}.yml"), encoding: 'UTF-8'))
    roteiro = File.read(@pasta.join("#{chave}.md"), encoding: 'UTF-8')
    Autonomia::Agents::ModelosDeRamo::Formato.new(chave: chave, dados: dados, roteiro: roteiro).modelo
  rescue Autonomia::Agents::ModelosDeRamo::Formato::Invalido => e
    fora(chave, e.message)
  rescue Psych::Exception, SystemCallError => e
    # Só a classe: a mensagem do erro de leitura pode trazer um trecho do arquivo.
    fora(chave, e.class.name)
  end

  def fora(chave, motivo)
    Rails.logger.error("#{LOG_TAG} modelo=#{chave} fora do ar: #{motivo}")
    nil
  end
end
