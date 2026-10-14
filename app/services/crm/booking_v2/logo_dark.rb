# A logo de fundo escuro de uma página de agendamento (#1295). A pessoa pode enviar a dela; sem isso, o sistema gera
# a partir da logo de fundo claro (`LogoDarkEngine`). De onde veio fica em `brand['logo_dark_source']`:
#
# - `uploaded`  a pessoa enviou (anexo `logo_dark`); trocar a logo de fundo claro não mexe nela;
# - `generated` o sistema gerou (anexo `logo_dark`);
# - `same`      a logo de fundo claro já se lê no escuro (sem anexo);
# - `plate`     não deu para gerar: a página escura mostra a logo de fundo claro numa placa clara (sem anexo).
#
# Sem valor (página de antes desta entrega, ou falha): a página pública trata como `plate`, que é o caso seguro.
#
# A origem e a imagem mudam juntas, com a página travada (`with_lock` relê o registro): dois pedidos ao mesmo tempo
# não deixam uma dizendo uma coisa e a outra mostrando outra. A conta da imagem é feita antes, fora da trava.
class Crm::BookingV2::LogoDark
  SOURCE_KEY = Crm::BookingPageSettings::LOGO_DARK_SOURCE
  UPLOADED = 'uploaded'.freeze
  PLATE = 'plate'.freeze
  # As origens que têm imagem própria (anexo `logo_dark`).
  IMAGE_SOURCES = [UPLOADED, 'generated'].freeze
  FILENAME = 'logo-fundo-escuro.png'.freeze

  def initialize(page)
    @page = page
  end

  def source
    page.brand.to_h[SOURCE_KEY]
  end

  # Há logo de fundo claro e a de fundo escuro ainda não foi resolvida: nunca foi olhada (página antiga, identidade
  # salva antes desta entrega) ou a origem promete uma imagem que não está lá.
  def pending?
    page.logo.attached? && (source.blank? || (IMAGE_SOURCES.include?(source) && !page.logo_dark.attached?))
  end

  # A pessoa enviou a própria logo de fundo escuro.
  def upload!(file)
    page.with_lock do
      page.logo_dark = file
      write_source(UPLOADED)
      page.save!
    end
  end

  # Gera a partir da logo de fundo claro, a não ser que a pessoa tenha enviado a dela. Não grava nem trava: é para a
  # página que ainda vai ser salva por quem chama (página nova, identidade salva).
  def assign_generated
    return page if !page.logo.attached? || keeps_upload?

    apply(engine_outcome)
    page
  end

  # Depois de trocar a logo de fundo claro. Um erro aqui (armazenamento fora do ar, por exemplo) não desfaz a logo
  # que acabou de ser salva: a página fica no caso seguro (placa) e o erro vai para o log. Se nem a placa puder ser
  # gravada, o erro sobe.
  def refresh!
    regenerate!(discard_upload: false)
  end

  # A pessoa desistiu da logo que enviou: volta para a gerada pelo sistema.
  def remove_upload!
    regenerate!(discard_upload: true)
  end

  private

  attr_reader :page

  def keeps_upload?
    source == UPLOADED && page.logo_dark.attached?
  end

  # A logo enviada pela pessoa fica, a não ser que ela tenha pedido para tirar.
  def upload_stays?(discard_upload)
    keeps_upload? && !discard_upload
  end

  def current_logo
    page.logo.blob if page.logo.attached?
  end

  def regenerate!(discard_upload:)
    logo = current_logo
    outcome = engine_outcome if logo && !upload_stays?(discard_upload)
    page.with_lock { store(outcome, logo, discard_upload) } if outcome || discard_upload
  rescue StandardError => e
    Rails.logger.error("[booking] logo para fundo escuro: #{e.class}: #{e.message.to_s.first(200)}")
    fall_back_to_plate!(discard_upload)
  end

  # Com a página travada e relida. Não grava por cima do que mudou enquanto a conta era feita: a logo enviada pela
  # pessoa nesse meio-tempo fica, e se a logo de fundo claro já é outra, quem a trocou gera a dela.
  def store(outcome, logo, discard_upload)
    return if upload_stays?(discard_upload) || current_logo != logo

    outcome ? apply(outcome) : clear
    page.save!
  end

  def apply(outcome)
    page.logo_dark = outcome.png && { io: StringIO.new(outcome.png), filename: FILENAME, content_type: 'image/png' }
    write_source(outcome.source)
  end

  def clear
    page.logo_dark = nil
    write_source(nil)
  end

  # O que o motor decidiu para a logo de fundo claro, com o motivo no log (é o que explica uma placa inesperada).
  def engine_outcome
    outcome = page.logo.blob.open { |file| Crm::BookingV2::LogoDarkEngine.call(file.read) }
    Rails.logger.info("[booking] logo para fundo escuro da página #{page.id.inspect}: #{outcome.source} (#{outcome.reason})")
    outcome
  end

  def write_source(value)
    page.brand = page.brand.to_h.merge(SOURCE_KEY => value).compact
  end

  # Relê antes de travar: o que a tentativa deixou pela metade na memória é descartado. A logo que a pessoa enviou
  # só sai se foi ela quem pediu para tirar.
  def fall_back_to_plate!(discard_upload)
    page.reload
    page.with_lock do
      next if upload_stays?(discard_upload)

      page.logo_dark = nil
      write_source(PLATE)
      page.save!
    end
  end
end
