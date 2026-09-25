# Planilha (.xlsx) da Lista do CRM (#722): os mesmos cards e na mesma ordem que a Lista
# mostra, sem o limite de página.
#
# Cada linha sai do Crm::Cards::PayloadBuilder, o mesmo que monta a Lista: o que a pessoa
# não pode ver na tela (etiquetas e campanhas de conversa que ela não vê) também não sai
# no arquivo, sem uma segunda cópia da regra.
#
# Toda célula de texto é gravada como texto (`:string`): um título "=HYPERLINK(...)" não
# vira fórmula ao abrir no Excel. Valor sai como número e datas como data, no fuso da
# conta (o mesmo que o CRM usa para agenda e follow-up). A aparência mora em
# Crm::Cards::XlsxExportStyles.
class Crm::Cards::XlsxExport
  BATCH_SIZE = 500
  HEADER_ROW = 4 # 1 título, 2 resumo, 3 respiro, 4 cabeçalho da tabela

  # Coluna => [tipo da célula, largura]. A ordem é a da planilha.
  LAYOUT = {
    title: [:text, 38], pipeline: [:text, 20], stage: [:text, 20], status: [:status, 13],
    value: [:value, 15], currency: [:text, 9], priority: [:priority, 12], contact: [:text, 28],
    phone: [:text, 18], email: [:text, 30], company: [:text, 24], responsible: [:text, 24],
    inbox: [:text, 22], labels: [:text, 28], campaign: [:text, 32], created_at: [:date, 17],
    last_activity_at: [:date, 17], next_follow_up_at: [:date, 17], closed_at: [:date, 17], lost_reason: [:text, 30]
  }.freeze
  COLUMNS = LAYOUT.keys.freeze
  CONTACT_COLUMNS = { contact: :name, phone: :phone_number, email: :email }.freeze
  CELL_TYPES = { text: :string, status: :string, priority: :string, value: :float, date: :time }.freeze

  def initialize(cards:, account:, user:, account_user:, pipeline: nil)
    @cards = cards
    @account = account
    @user = user
    @account_user = account_user
    @pipeline = pipeline
  end

  def filename
    "#{I18n.t('crm.export.file_prefix')}-#{now.strftime('%Y-%m-%d')}.xlsx"
  end

  def generate
    package.to_stream.read
  end

  # O pacote montado, exposto para validar o arquivo contra o schema do formato (specs).
  def package
    @package ||= Axlsx::Package.new.tap do |pacote|
      pacote.use_shared_strings = true
      pacote.workbook.add_worksheet(name: I18n.t('crm.export.sheet_name')) { |sheet| build(sheet, pacote.workbook) }
    end
  end

  private

  def build(sheet, workbook)
    styles = Crm::Cards::XlsxExportStyles.new(workbook)
    add_title(sheet, styles)
    sheet.add_row(COLUMNS.map { |column| I18n.t("crm.export.columns.#{column}") },
                  style: styles.header, types: COLUMNS.map { :string }, height: 28)
    each_card.with_index { |card, index| add_card_row(sheet, styles, card, index.odd?) }
    finish(sheet)
  end

  def add_title(sheet, styles)
    sheet.add_row([@pipeline&.name || I18n.t('crm.export.title_fallback')], style: styles.title, types: [:string], height: 26)
    subtitle = I18n.t('crm.export.subtitle', date: I18n.l(now, format: '%d/%m/%Y %H:%M'), count: total)
    sheet.add_row([subtitle], style: styles.subtitle, types: [:string], height: 18)
    sheet.add_row([], height: 8)
  end

  def add_card_row(sheet, styles, card, zebra)
    payload = Crm::Cards::PayloadBuilder.new(card, user: @user, account_user: @account_user,
                                                   conversation_visibility: conversation_visibility).perform
    cells = COLUMNS.map { |column| cell_value(column, card, payload) }
    row_styles = COLUMNS.map { |column| styles.cell(LAYOUT[column].first, zebra: zebra, raw: raw_enum(column, card)) }
    sheet.add_row(cells, types: COLUMNS.map { |column| CELL_TYPES[LAYOUT[column].first] }, style: row_styles, height: 20)
  end

  def finish(sheet)
    sheet.column_widths(*LAYOUT.values.map(&:last))
    add_table(sheet)
    sheet.sheet_view.show_grid_lines = false
    sheet.sheet_view.pane do |pane|
      pane.state = :frozen
      pane.x_split = 1
      pane.y_split = HEADER_ROW
      pane.top_left_cell = "B#{HEADER_ROW + 1}"
    end
    sheet.page_setup.set(orientation: :landscape, fit_to_width: 1, fit_to_height: 0)
    sheet.print_options.horizontal_centered = true
    # Impresso em várias páginas, o cabeçalho da tabela se repete no topo de cada uma.
    sheet.workbook.add_defined_name("'#{sheet.name}'!$#{HEADER_ROW}:$#{HEADER_ROW}",
                                    name: '_xlnm.Print_Titles', local_sheet_id: sheet.index)
  end

  # Tabela do Excel ("Formatar como Tabela") sobre o cabeçalho e os dados: botões de filtro e
  # ordenação no cabeçalho. Não é `sheet.auto_filter`: o caxlsx 4.5 grava o nome interno
  # do filtro (_xlnm._FilterDatabase) duas vezes, e o Excel oferece "reparar" o arquivo.
  # O estilo da tabela fica neutro e sem listras: quem pinta é o XlsxExportStyles.
  def add_table(sheet)
    last_row = HEADER_ROW + [total, 1].max
    sheet.add_table("A#{HEADER_ROW}:#{Axlsx.col_ref(COLUMNS.size - 1)}#{last_row}",
                    name: 'Cards', style_info: { name: 'TableStyleLight1', show_row_stripes: false })
  end

  # A ordem vem do FilterQuery (a da Lista, com desempate por id); lotes por offset a
  # preservam, o que find_each não faria.
  def each_card(&block)
    return enum_for(:each_card) unless block

    offset = 0
    loop do
      batch = @cards.limit(BATCH_SIZE).offset(offset).to_a
      break if batch.empty?

      batch.each(&block)
      offset += BATCH_SIZE
    end
  end

  def raw_enum(column, card)
    return card.status if column == :status

    card.priority if column == :priority
  end

  def cell_value(column, card, payload)
    case LAYOUT[column].first
    when :value then card.value_cents && (card.value_cents / 100.0)
    when :date then card.public_send(column)&.in_time_zone(zone)
    else text_value(column, card, payload)
    end
  end

  def text_value(column, card, payload)
    case column
    when :pipeline, :stage, :inbox then payload.dig(column, :name)
    when :status then I18n.t("crm.export.statuses.#{card.status}", default: card.status)
    when :priority then card.priority && I18n.t("crm.export.priorities.#{card.priority}", default: card.priority)
    when *CONTACT_COLUMNS.keys then payload.dig(:contact, CONTACT_COLUMNS[column])
    else relation_text(column, card, payload)
    end
  end

  def relation_text(column, card, payload)
    case column
    when :company then payload.dig(:contact, :additional_attributes, 'company_name')
    when :responsible then payload.dig(:responsible, :name)
    when :labels then (Array(payload[:labels]) | Array(payload[:contact_labels])).join(', ').presence
    when :campaign then campaign_text(payload)
    else card.public_send(column)
    end
  end

  # A primeira origem (o toque que trouxe o lead), como o card mostra.
  def campaign_text(payload)
    first_touch = Array(payload[:campaigns]).first
    return if first_touch.blank?

    [first_touch[:source], first_touch[:headline]].compact_blank.join(' — ')
  end

  def total
    @total ||= @cards.count
  end

  def now
    @now ||= Time.current.in_time_zone(zone)
  end

  def conversation_visibility
    @conversation_visibility ||= Crm::Conversations::Visibility.new(account: @account, user: @user, account_user: @account_user)
  end

  def zone
    @zone ||= Crm::Timezone::Resolver.new(account: @account).zone_or_default
  end
end
