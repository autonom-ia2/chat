# frozen_string_literal: true

# Textos dos pacotes de tradução do servidor (#1550): config/pacotes/<camada>/<idioma>.yml, com raiz no idioma.
# Hash próprio, congelado e lido uma vez por processo (editou o yml, reinicie o servidor). Não instancia outro
# I18n::Backend::Simple: o lookup do pacote não pode chamar o I18n de novo.
module Autonomia::Segmentos::Catalogo
  PASTA = Rails.root.join('config/pacotes')
  MUTEX = Mutex.new
  LOG_TAG = '[Autonomia::Segmentos::Catalogo]'

  # A camada mais específica (a última) vence. Só devolve folha String: pedido de subárvore segue no base.
  def self.procurar(locale, key, scope, separator, camadas)
    chaves = I18n.normalize_keys(locale, key, scope, separator)
    camadas.reverse_each do |camada|
      valor = descer(dados[camada], chaves)
      return valor if valor.is_a?(String)
    end
    nil
  end

  # Um yml ilegível não derruba o I18n de quem está no pacote: o processo fica com o catálogo base até reiniciar, e
  # a falha é lida uma vez só. O check `Fork translations` do CI barra o yml inválido antes do deploy.
  def self.dados
    @dados || MUTEX.synchronize { @dados ||= carregar_ou_vazio }
  end

  def self.carregar_ou_vazio
    carregar.freeze
  rescue StandardError => e
    # Só a classe: a mensagem do parser traz trecho do arquivo.
    Rails.logger.error("#{LOG_TAG} #{e.class} ao ler #{PASTA}; pacotes do servidor no catálogo base até reiniciar")
    {}.freeze
  end
  private_class_method :carregar_ou_vazio

  def self.carregar
    Dir.glob(PASTA.join('**', '*.yml').to_s).each_with_object({}) do |arquivo, acc|
      camada = Pathname(arquivo).relative_path_from(PASTA).dirname.to_s
      conteudo = (YAML.safe_load_file(arquivo) || {}).deep_symbolize_keys
      acc[camada] = (acc[camada] || {}).deep_merge(conteudo)
    end
  end
  private_class_method :carregar

  # Como o dig, mas para no meio sem erro quando o caminho atravessa um texto.
  def self.descer(arvore, chaves)
    chaves.reduce(arvore) do |no, chave|
      return nil unless no.is_a?(Hash)

      no[chave]
    end
  end
  private_class_method :descer
end
