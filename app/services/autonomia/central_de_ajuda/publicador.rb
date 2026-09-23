# Publica a Central de Ajuda "Plataforma" do repositório (`lib/central_de_ajuda/`) no portal do Chatwoot.
#
# Um portal por instalação, o "plataforma". Ele mora na conta que já o tem ou, na primeira publicação,
# na conta mais antiga da instalação; quem lê é a tela de leitura, aberta a todas as contas, então a
# conta dona não muda nada para o leitor. Uma categoria por capítulo e um artigo por arquivo. Idempotente: artigo sem
# mudança não é regravado (o sha do conteúdo fica em `meta`). Artigo que saiu do repositório é
# arquivado, nunca apagado. Publica artigo por artigo, fora de uma transação única: a falha de um não
# derruba nem apaga os outros, que o cliente pode estar lendo.
#
# Como o seed do Guia, roda sozinho depois de cada deploy: `garantir_async` (chamado na subida do Sidekiq
# e por quem lê a Central) enfileira o job quando a versão embarcada ainda não foi publicada.
class Autonomia::CentralDeAjuda::Publicador
  FONTE = Rails.root.join('lib/central_de_ajuda')
  MAPA = Rails.root.join('docs/central-de-ajuda/mapa-de-artigos.json')
  SLUG_PORTAL = 'plataforma'.freeze
  NOME_PORTAL = 'Central de Ajuda'.freeze
  LOCALE = 'pt_BR'.freeze
  LOCK_NS = 4_343
  VERSAO_DO_PUBLICADOR = 1 # suba quando mudar o que a publicação grava, para republicar tudo

  class Conflito < StandardError; end

  Resultado = Struct.new(:criados, :atualizados, :iguais, :arquivados, :falhas, keyword_init: true) do
    def ok? = falhas.empty?
    def to_s = "criados=#{criados} atualizados=#{atualizados} iguais=#{iguais} arquivados=#{arquivados} falhas=#{falhas.size}"
  end

  def self.conta
    ::Portal.find_by(slug: SLUG_PORTAL)&.account || ::Account.order(:id).first
  end

  # Os arquivos vêm na imagem e não mudam com o processo no ar: calcula uma vez (em dev, a cada chamada).
  def self.versao
    return calcular_versao if Rails.env.development?

    @versao ||= calcular_versao
  end

  def self.calcular_versao
    arquivos = Dir[FONTE.join('*/*.md')]
    conteudo = arquivos.map { |f| "#{f.delete_prefix(FONTE.to_s)}\0#{File.read(f)}" }.join("\0")
    Digest::SHA256.hexdigest("#{VERSAO_DO_PUBLICADOR}\0#{File.read(MAPA)}\0#{conteudo}")[0, 16]
  end

  def self.chave_publicado = "autonomia:central_de_ajuda:publicado:#{versao}"

  def self.publicado? = Rails.cache.read(chave_publicado).present?

  # Chamado a cada leitura da Central: barato quando já publicado (só o cache); senão, enfileira uma vez
  # a cada 5 min.
  def self.garantir_async
    return true if publicado?
    return false if conta.nil?

    Rails.cache.fetch("autonomia:central_de_ajuda:enfileirado:#{versao}", expires_in: 5.minutes) do
      ::Autonomia::CentralDeAjuda::PublicarJob.perform_later
      true
    end
  rescue StandardError => e
    Rails.logger.warn("[central_de_ajuda][publicador] enfileirar_falhou #{e.class}: #{e.message}")
    false
  end

  def initialize(conta = self.class.conta)
    @conta = conta
  end

  # Devolve o Resultado, ou nil quando outra publicação já está em curso (a outra instância do blue/green).
  def publicar!
    raise Conflito, 'a instalação não tem nenhuma conta' if @conta.nil?

    com_lock do
      resultado = publicar_tudo
      Rails.cache.write(self.class.chave_publicado, Time.current.iso8601) if resultado.ok?
      resultado
    end
  end

  private

  def publicar_tudo
    @resultado = Resultado.new(criados: 0, atualizados: 0, iguais: 0, arquivados: 0, falhas: [])
    @portal = garantir_portal
    @autor = @conta.administrators.order(:id).first
    raise Conflito, "conta #{@conta.id} sem administrador para assinar os artigos" if @autor.nil?

    fontes.each { |fonte| publicar_artigo(fonte) }
    arquivar_ausentes(slugs_no_repositorio)
    Rails.logger.info("[central_de_ajuda][publicador] conta=#{@conta.id} #{@resultado}")
    @resultado
  end

  def mapa
    @mapa ||= JSON.parse(File.read(MAPA))
  end

  def titulos
    @titulos ||= mapa['capitulos'].flat_map { |c| c['artigos'].map { |a| [a['id'], a['titulo']] } }.to_h
  end

  def arquivos = Dir[FONTE.join('*/*.md')]

  # Arquivo com cabeçalho quebrado vira falha e não é publicado, mas o artigo dele continua no ar.
  def fontes
    @fontes ||= arquivos.filter_map do |caminho|
      ::Autonomia::CentralDeAjuda::ArtigoFonte.new(caminho, titulos: titulos)
    rescue StandardError => e
      registrar_falha(caminho, e)
    end
  end

  # O slug sai do nome do arquivo (`02.06-...md`), não do cabeçalho: um arquivo que não abriu não pode
  # fazer o artigo dele parecer removido do repositório.
  def slugs_no_repositorio
    arquivos.map { |caminho| ::Autonomia::CentralDeAjuda::ArtigoFonte.slug_de(File.basename(caminho).split('-').first) }
  end

  def garantir_portal
    portal = ::Portal.find_by(slug: SLUG_PORTAL)
    raise Conflito, "o portal '#{SLUG_PORTAL}' já existe na conta #{portal.account_id}" if portal && portal.account_id != @conta.id

    portal || @conta.portals.create!(
      name: NOME_PORTAL, slug: SLUG_PORTAL, page_title: NOME_PORTAL,
      config: { 'allowed_locales' => [LOCALE], 'default_locale' => LOCALE }
    )
  end

  def categoria(capitulo_id)
    @categorias ||= {}
    @categorias[capitulo_id] ||= begin
      capitulo = mapa['capitulos'].find { |c| c['id'] == capitulo_id }
      raise Conflito, "capítulo #{capitulo_id} fora do mapa" if capitulo.nil?

      cat = @portal.categories.find_or_initialize_by(slug: "capitulo-#{capitulo_id}", locale: LOCALE)
      cat.assign_attributes(name: capitulo['titulo'], position: capitulo_id.to_i)
      cat.save! if cat.changed?
      cat
    end
  end

  def publicar_artigo(fonte)
    artigo = ::Article.find_by(slug: fonte.slug)
    raise Conflito, "slug #{fonte.slug} já usado no portal #{artigo.portal_id}" if artigo && artigo.portal_id != @portal.id

    artigo ||= @portal.articles.new(slug: fonte.slug)
    return contar(:iguais) if igual?(artigo, fonte)

    novo = artigo.new_record?
    artigo.assign_attributes(atributos(fonte, artigo))
    artigo.save!
    manter_posicao(artigo, fonte)
    contar(novo ? :criados : :atualizados)
  rescue StandardError => e
    registrar_falha(fonte.caminho, e)
  end

  def registrar_falha(caminho, erro)
    Rails.logger.error("[central_de_ajuda][publicador] artigo=#{caminho} #{erro.class}: #{erro.message}")
    @resultado.falhas << caminho
    nil
  end

  def igual?(artigo, fonte)
    artigo.persisted? && artigo.published? && artigo.meta.to_h.dig('central', 'sha') == fonte.sha
  end

  def atributos(fonte, artigo)
    {
      title: fonte.titulo, content: fonte.conteudo, description: fonte.descricao,
      category: categoria(fonte.capitulo), author: @autor, status: :published, locale: LOCALE,
      position: posicao(fonte), meta: artigo.meta.to_h.merge('central' => fonte.meta)
    }
  end

  # Artigo que mudou de capítulo: o callback do Article joga a posição para o fim da categoria nova
  # (Article#category_id_changed_action). A ordem da Central vem do id, então ela é regravada.
  def manter_posicao(artigo, fonte)
    return unless artigo.saved_change_to_category_id? && artigo.position != posicao(fonte)

    artigo.update_column(:position, posicao(fonte)) # rubocop:disable Rails/SkipsModelValidations
  end

  # Ordem dentro do capítulo: 02.06 fica na posição 60.
  def posicao(fonte) = fonte.id.split('.').last.to_i * 10

  def arquivar_ausentes(slugs_atuais)
    @portal.articles.where('slug LIKE ?', "#{::Autonomia::CentralDeAjuda::ArtigoFonte::PREFIXO_SLUG}%")
           .where.not(slug: slugs_atuais).where.not(status: :archived).find_each do |artigo|
      artigo.update!(status: :archived)
      contar(:arquivados)
    end
  end

  def contar(campo)
    @resultado[campo] += 1
    true
  end

  # Lock de sessão sem espera (mesmo padrão de EmailCampaigns::Reputation::CampaignDeliveryLock): se a outra
  # instância do blue/green já está publicando, esta desiste em vez de prender um worker na fila.
  def com_lock
    ::ActiveRecord::Base.connection_pool.with_connection do |conn|
      return nil unless conn.select_value("SELECT pg_try_advisory_lock(#{LOCK_NS}, #{@conta.id.to_i})")

      begin
        yield
      ensure
        conn.select_value("SELECT pg_advisory_unlock(#{LOCK_NS}, #{@conta.id.to_i})")
      end
    end
  end
end
