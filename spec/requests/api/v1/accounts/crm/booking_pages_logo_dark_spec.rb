require 'rails_helper'

# Logo para fundo escuro das páginas de agendamento (#1295): a pessoa envia a dela ou o sistema gera a partir da logo;
# de onde veio fica em `brand.logo_dark_source`. O motor de imagem (`LogoDarkEngine`) tem spec próprio; aqui ele é
# trocado por uma resposta pronta, menos no exemplo que roda de ponta a ponta.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages logo dark', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:page) { world.profile }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }
  let(:engine) { Crm::BookingV2::LogoDarkEngine }
  let(:png) { Rails.root.join('spec/assets/avatar.png').binread }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    engine_returns('generated', png)
  end

  def engine_returns(source, bytes = nil)
    allow(engine).to receive(:call).and_return(engine::Outcome.new(source: source, png: bytes, reason: :spec))
  end

  def file(name = 'avatar.png')
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets', name), 'image/png')
  end

  def upload(user, kind, upload = file, target: page)
    post "#{base}/#{target.id}/#{kind}", params: { file: upload }, headers: user.create_new_auth_token
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def source_of(target = page)
    target.reload.brand['logo_dark_source']
  end

  describe 'POST logo' do
    it 'gera a logo de fundo escuro a partir da logo enviada e devolve as duas' do
      upload(admin, :logo)

      expect(response).to have_http_status(:ok)
      expect(engine).to have_received(:call).with(png)
      expect(page.reload.logo_dark).to be_attached
      expect(page.logo_dark.blob).to have_attributes(content_type: 'image/png', filename: ActiveStorage::Filename.new('logo-fundo-escuro.png'))
      expect(source_of).to eq('generated')
      expect(body['payload']).to include('logo_url' => be_present, 'logo_dark_url' => be_present)
      expect(body.dig('payload', 'brand', 'logo_dark_source')).to eq('generated')
    end

    it 'logo que já se lê no escuro: não guarda segunda imagem' do
      engine_returns('same')

      upload(admin, :logo)

      expect(page.reload.logo_dark).not_to be_attached
      expect(source_of).to eq('same')
      expect(body['payload']).to include('logo_dark_url' => nil)
    end

    it 'quando não dá para gerar, a página fica na placa' do
      engine_returns('plate')

      upload(admin, :logo)

      expect(page.reload.logo_dark).not_to be_attached
      expect(source_of).to eq('plate')
    end

    it 'trocar a logo gera a de fundo escuro de novo e tira a gerada anterior' do
      upload(admin, :logo)
      engine_returns('plate')

      upload(admin, :logo, file('sample.png'))

      expect(page.reload.logo_dark).not_to be_attached
      expect(source_of).to eq('plate')
    end

    it 'erro ao gerar não derruba a logo enviada: fica salva, na placa' do
      allow(engine).to receive(:call).and_raise(ActiveStorage::FileNotFoundError)

      upload(admin, :logo)

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo).to be_attached
      expect(page.logo_dark).not_to be_attached
      expect(source_of).to eq('plate')
    end

    it 'logo recusada (SVG) não gera nada' do
      svg = Tempfile.new(['logo', '.png'])
      svg.write('<svg xmlns="http://www.w3.org/2000/svg"></svg>')
      svg.rewind

      upload(admin, :logo, Rack::Test::UploadedFile.new(svg.path, 'image/png', original_filename: 'logo.png'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(engine).not_to have_received(:call)
      expect(page.reload.logo).not_to be_attached
      expect(source_of).to be_nil
    end

    it 'de ponta a ponta, com a libvips: logo com transparência vira uma imagem para fundo escuro ou é aproveitada' do
      begin
        require 'image_processing/vips'
      rescue LoadError => e
        skip "libvips indisponível nesta máquina: #{e.class}"
      end
      allow(engine).to receive(:call).and_call_original
      logo = Tempfile.new(['logo', '.png'])
      logo.binmode
      logo.write(Vips::Image.black(80, 40).bandjoin([0, 0, 255]).cast(:uchar).copy(interpretation: :srgb)
                            .draw_rect([13, 35, 68, 255], 10, 10, 60, 20, fill: true).pngsave_buffer)
      logo.rewind

      upload(admin, :logo, Rack::Test::UploadedFile.new(logo.path, 'image/png'))

      expect(response).to have_http_status(:ok)
      expect(source_of).to eq('generated')
      generated = Vips::Image.new_from_buffer(page.reload.logo_dark.download, '')
      expect(generated.getpoint(40, 20)).to eq([255, 255, 255, 255])
      expect(generated.getpoint(1, 1).last).to eq(0)
    end
  end

  describe 'POST logo_dark' do
    it 'guarda a logo que a pessoa enviou para o fundo escuro' do
      upload(admin, :logo)

      upload(admin, :logo_dark, file('sample.png'))

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo_dark.blob.filename.to_s).to eq('sample.png')
      expect(source_of).to eq('uploaded')
      expect(body.dig('payload', 'brand', 'logo_dark_source')).to eq('uploaded')
    end

    it 'trocar a logo de fundo claro depois não mexe na que a pessoa enviou' do
      upload(admin, :logo)
      upload(admin, :logo_dark, file('sample.png'))
      enviada = page.reload.logo_dark.blob

      upload(admin, :logo, file('sample.png'))

      expect(page.reload.logo_dark.blob).to eq(enviada)
      expect(source_of).to eq('uploaded')
      expect(engine).to have_received(:call).once
    end

    it 'erro ao gerar enquanto a pessoa envia a dela: a dela fica, não vira placa' do
      upload(admin, :logo)
      allow(engine).to receive(:call) do
        Crm::BookingV2::LogoDark.new(Crm::AgentBookingProfile.find(page.id)).upload!(file('sample.png'))
        raise ActiveStorage::FileNotFoundError
      end

      upload(admin, :logo, file('sample.png'))

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo_dark.blob.filename.to_s).to eq('sample.png')
      expect(source_of).to eq('uploaded')
    end

    it 'a pessoa envia a dela enquanto a nossa é gerada: fica a dela' do
      upload(admin, :logo)
      allow(engine).to receive(:call) do
        Crm::BookingV2::LogoDark.new(Crm::AgentBookingProfile.find(page.id)).upload!(file('sample.png'))
        engine::Outcome.new(source: 'plate', png: nil, reason: :spec)
      end

      upload(admin, :logo, file('sample.png'))

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo_dark.blob.filename.to_s).to eq('sample.png')
      expect(source_of).to eq('uploaded')
    end

    it 'recusa SVG e arquivo acima de 2 MB, como a logo, e deixa a gerada como estava' do
      upload(admin, :logo)
      svg = Tempfile.new(['logo', '.png'])
      svg.write('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
      svg.rewind
      upload(admin, :logo_dark, Rack::Test::UploadedFile.new(svg.path, 'image/png', original_filename: 'logo.png'))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to include('PNG, JPEG or WebP')

      big = Tempfile.new(['big', '.png'])
      big.binmode
      big.write("\x89PNG\r\n\x1a\n".b + ("\0".b * 3.megabytes))
      big.rewind
      upload(admin, :logo_dark, Rack::Test::UploadedFile.new(big.path, 'image/png'))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to include('too large')

      expect(page.reload.logo_dark.blob.filename.to_s).to eq('logo-fundo-escuro.png')
      expect(source_of).to eq('generated')
    end

    it 'recusa pedido sem arquivo' do
      upload(admin, :logo)

      upload(admin, :logo_dark, nil)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.file_missing')
    end

    it 'página sem logo não aceita a de fundo escuro: ela ficaria solta, sem aparecer' do
      upload(admin, :logo_dark)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.logo_missing')
      expect(page.reload.logo_dark).not_to be_attached
      expect(source_of).to be_nil
    end
  end

  describe 'DELETE logo_dark' do
    it 'tira a enviada e volta para a gerada pelo sistema' do
      upload(admin, :logo)
      upload(admin, :logo_dark, file('sample.png'))

      call(admin, :delete, "#{base}/#{page.id}/logo_dark")

      expect(response).to have_http_status(:ok)
      expect(source_of).to eq('generated')
      expect(page.reload.logo_dark.blob.filename.to_s).to eq('logo-fundo-escuro.png')
    end

    it 'página sem logo: não há o que tirar nem o que gerar' do
      call(admin, :delete, "#{base}/#{page.id}/logo_dark")

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo_dark).not_to be_attached
      expect(source_of).to be_nil
      expect(engine).not_to have_received(:call)
    end

    it 'erro ao gerar de novo: a enviada sai e a página fica na placa' do
      upload(admin, :logo)
      upload(admin, :logo_dark, file('sample.png'))
      allow(engine).to receive(:call).and_raise(ActiveStorage::FileNotFoundError)

      call(admin, :delete, "#{base}/#{page.id}/logo_dark")

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo_dark).not_to be_attached
      expect(source_of).to eq('plate')
    end
  end

  describe 'PATCH update' do
    it 'salvar cor, frase e lado não apaga de onde veio a logo de fundo escuro' do
      upload(admin, :logo)

      call(admin, :patch, "#{base}/#{page.id}", { brand: { color: '#ffe066', headline: 'Oi', logo_align: 'right' } })

      expect(response).to have_http_status(:ok)
      expect(page.reload.brand).to eq({ 'color' => '#ffe066', 'headline' => 'Oi', 'logo_align' => 'right', 'logo_dark_source' => 'generated' })
      expect(page.logo_dark).to be_attached
    end

    it 'a origem não é aceita do formulário' do
      upload(admin, :logo)

      call(admin, :patch, "#{base}/#{page.id}", { brand: { color: '#ffe066', logo_dark_source: 'uploaded' } })

      expect(source_of).to eq('generated')
    end

    it 'página com logo de antes desta entrega ganha a de fundo escuro na primeira vez que é salva' do
      page.logo.attach(io: StringIO.new(png), filename: 'avatar.png', content_type: 'image/png')
      expect(source_of).to be_nil

      call(admin, :patch, "#{base}/#{page.id}", { title: 'Conversa' })

      expect(source_of).to eq('generated')
      expect(page.reload.logo_dark).to be_attached
      expect(engine).to have_received(:call).once

      call(admin, :patch, "#{base}/#{page.id}", { title: 'Outra conversa' })
      expect(engine).to have_received(:call).once
    end

    it 'origem que promete uma imagem que não está mais lá é resolvida ao salvar' do
      upload(admin, :logo)
      page.reload.logo_dark.detach

      call(admin, :patch, "#{base}/#{page.id}", { title: 'Conversa' })

      expect(page.reload.logo_dark).to be_attached
      expect(source_of).to eq('generated')
      expect(engine).to have_received(:call).twice
    end

    # Dois pedidos ao mesmo tempo: a pessoa envia a logo de fundo escuro depois que o "salvar" já leu a página (a
    # policy é montada logo depois dessa leitura) e antes de ele gravar.
    it 'vale a origem que está no banco na hora de gravar, não a de quando o pedido começou' do
      upload(admin, :logo)
      interleaved = false
      allow(Crm::BookingPagePolicy).to receive(:new).and_wrap_original do |original, *args|
        unless interleaved
          interleaved = true
          Crm::BookingV2::LogoDark.new(Crm::AgentBookingProfile.find(page.id)).upload!(file('sample.png'))
        end
        original.call(*args)
      end

      call(admin, :patch, "#{base}/#{page.id}", { brand: { color: '#ffe066' } })

      expect(interleaved).to be(true)

      expect(source_of).to eq('uploaded')
      expect(page.reload.logo_dark.blob.filename.to_s).to eq('sample.png')
    end

    it 'página sem logo não chama o motor' do
      call(admin, :patch, "#{base}/#{page.id}", { title: 'Conversa' })

      expect(engine).not_to have_received(:call)
      expect(page.reload.brand).not_to have_key('logo_dark_source')
    end
  end

  describe 'modelo' do
    it 'só aceita as quatro origens conhecidas' do
      %w[uploaded generated same plate].each do |source|
        page.brand = { 'logo_dark_source' => source }
        expect(page).to be_valid
      end
      page.brand = { 'logo_dark_source' => 'qualquer' }
      expect(page).not_to be_valid
      expect(page.errors[:brand]).to include('invalid dark logo source')
    end
  end

  describe 'permissão' do
    it 'quem gerencia páginas envia e tira; quem só vê e o agente comum, não' do
      manager = role_user('agendamento_manage')
      viewer = role_user('agendamento_view')
      agent = create(:user, account: account, role: :agent)

      upload(manager, :logo)
      upload(manager, :logo_dark, file('sample.png'))
      expect(response).to have_http_status(:ok)
      call(manager, :delete, "#{base}/#{page.id}/logo_dark")
      expect(response).to have_http_status(:ok)

      [viewer, agent].each do |user|
        upload(user, :logo_dark)
        expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
        call(user, :delete, "#{base}/#{page.id}/logo_dark")
        expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      end
      expect(source_of).to eq('generated')
      expect(page.reload.logo_dark.blob.filename.to_s).to eq('logo-fundo-escuro.png')
    end

    it 'página de outra conta não existe para quem pede' do
      other_account = create(:account)
      other_account.enable_features('crm_booking_v2')
      other_account.save!
      other = build_booking_world(account: other_account).profile

      upload(admin, :logo_dark, target: other)
      expect(response).to have_http_status(:not_found)
      post "#{base}/#{other.id}/logo_dark", params: { file: file },
                                            headers: create(:user, account: other_account, role: :administrator).create_new_auth_token
      expect(response).to have_http_status(:unauthorized).or have_http_status(:not_found)
      expect(other.reload.logo_dark).not_to be_attached
    end

    it 'com a flag da conta desligada, 404' do
      account.disable_features('crm_booking_v2')
      account.save!

      upload(admin, :logo_dark)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'identidade salva' do
    let(:identity) { Crm::BookingV2::BrandIdentity.new(account.reload) }

    it 'salvar leva as duas logos e de onde veio a de fundo escuro' do
      upload(admin, :logo)
      upload(admin, :logo_dark, file('sample.png'))
      call(admin, :post, "#{base}/#{page.id}/save_identity")

      expect(response).to have_http_status(:ok)
      expect(account.reload.booking_identity_logo.blob).to eq(page.reload.logo.blob)
      expect(account.booking_identity_logo_dark.blob).to eq(page.logo_dark.blob)
      expect(account.settings['booking_identity']).to include('logo_dark_source' => 'uploaded')
      expect(body.dig('payload', 'identity')).to include('logo_url' => be_present, 'logo_dark_url' => be_present)
    end

    it 'usar traz as duas logos para outra página, sem gerar de novo' do
      upload(admin, :logo)
      upload(admin, :logo_dark, file('sample.png'))
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      other = create_booking_profile(account: account, host: world.host, brand: { 'color' => '#0D2344' })

      call(admin, :post, "#{base}/#{other.id}/apply_identity")

      expect(response).to have_http_status(:ok)
      expect(other.reload.logo.blob).to eq(page.reload.logo.blob)
      expect(other.logo_dark.blob).to eq(page.logo_dark.blob)
      expect(source_of(other)).to eq('uploaded')
      expect(engine).to have_received(:call).once
    end

    it 'identidade de logo que serve no escuro tira a logo de fundo escuro que a página tinha' do
      engine_returns('same')
      upload(admin, :logo)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      other = create_booking_profile(account: account, host: world.host)
      upload(admin, :logo, target: other)
      upload(admin, :logo_dark, file('sample.png'), target: other)

      call(admin, :post, "#{base}/#{other.id}/apply_identity")

      expect(other.reload.logo_dark).not_to be_attached
      expect(source_of(other)).to eq('same')
      expect(account.reload.booking_identity_logo_dark).not_to be_attached
    end

    it 'salvar de novo sem logo de fundo escuro tira a que estava salva' do
      upload(admin, :logo)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      expect(account.reload.booking_identity_logo_dark).to be_attached

      engine_returns('plate')
      upload(admin, :logo, file('sample.png'))
      call(admin, :post, "#{base}/#{page.id}/save_identity")

      expect(account.reload.booking_identity_logo_dark).not_to be_attached
      expect(account.settings['booking_identity']).to include('logo_dark_source' => 'plate')
    end

    it 'página sem logo não mexe nas logos nem na origem já salvas' do
      upload(admin, :logo)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      bare = create_booking_profile(account: account, host: world.host, brand: { 'color' => '#0D2344' })

      call(admin, :post, "#{base}/#{bare.id}/save_identity")

      expect(account.reload.booking_identity_logo).to be_attached
      expect(account.booking_identity_logo_dark).to be_attached
      expect(account.settings['booking_identity']).to include('color' => '#0D2344', 'logo_dark_source' => 'generated')
    end

    it 'identidade salva antes desta entrega (sem origem): a de fundo escuro é gerada ao usar' do
      account.booking_identity_logo.attach(io: StringIO.new(png), filename: 'avatar.png', content_type: 'image/png')
      account.update!(settings: account.settings.to_h.merge('booking_identity' => { 'color' => '#0D2344' }))
      other = create_booking_profile(account: account, host: world.host)

      call(admin, :post, "#{base}/#{other.id}/apply_identity")

      expect(response).to have_http_status(:ok)
      expect(other.reload.logo_dark).to be_attached
      expect(source_of(other)).to eq('generated')
    end

    it 'página nova já nasce com as duas logos da identidade' do
      upload(admin, :logo)
      call(admin, :post, "#{base}/#{page.id}/save_identity")

      call(admin, :post, base, { template_key: 'sales_30' })

      expect(response).to have_http_status(:created)
      created = Crm::AgentBookingProfile.find(body.dig('payload', 'id'))
      expect(created.logo.blob).to eq(page.reload.logo.blob)
      expect(created.logo_dark.blob).to eq(page.logo_dark.blob)
      expect(source_of(created)).to eq('generated')
    end

    it 'trocar a logo de fundo escuro da página depois não derruba a da identidade' do
      upload(admin, :logo)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      saved = account.reload.booking_identity_logo_dark.blob

      perform_enqueued_jobs { upload(admin, :logo_dark, file('sample.png')) }

      expect(ActiveStorage::Blob.exists?(saved.id)).to be(true)
      expect(account.reload.booking_identity_logo_dark.blob).to eq(saved)
      expect(saved.download).to be_present
    end
  end

  describe 'página pública' do
    let(:public_path) { "/public/api/v2/booking/#{page.slug}" }

    it 'sem logo: nada de logo de fundo escuro' do
      get public_path

      expect(body['brand']).to include('logo_url' => nil, 'logo_dark_url' => nil, 'logo_dark_source' => nil)
    end

    it 'entrega a logo de fundo escuro e de onde ela veio' do
      upload(admin, :logo)

      get public_path

      expect(body['brand']).to include('logo_url' => be_present, 'logo_dark_url' => be_present, 'logo_dark_source' => 'generated')
      expect(body.dig('brand', 'logo_dark_url')).not_to eq(body.dig('brand', 'logo_url'))
    end

    it 'logo na placa: sem segunda imagem, e a origem diz que é placa' do
      engine_returns('plate')
      upload(admin, :logo)

      get public_path

      expect(body['brand']).to include('logo_url' => be_present, 'logo_dark_url' => nil, 'logo_dark_source' => 'plate')
    end

    it 'página pausada também entrega as duas' do
      upload(admin, :logo)
      page.update!(enabled: false)

      get public_path

      expect(body).to include('paused' => true)
      expect(body['brand']).to include('logo_dark_url' => be_present, 'logo_dark_source' => 'generated')
    end
  end

  # Tipo real do arquivo (#1303): a logo de fundo escuro passa pela mesma conferência da logo e da foto
  # (`Crm::BookingV2::ImageFile`), enviada pela pessoa, gerada pelo motor ou copiada da identidade salva.
  describe 'conferência do tipo real' do
    let(:identity) { Crm::BookingV2::BrandIdentity.new(account.reload) }
    let(:svg) { %(#{' ' * 5000}<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>) }

    def disguised(name = 'logo-escura.png')
      tmp = Tempfile.new([File.basename(name, '.*'), File.extname(name)])
      tmp.binmode
      tmp.write(svg)
      tmp.rewind
      Rack::Test::UploadedFile.new(tmp.path, 'image/png')
    end

    it 'recusa a logo de fundo escuro disfarçada, com o motivo, e deixa a gerada como estava' do
      upload(admin, :logo)
      generated = page.reload.logo_dark.blob

      upload(admin, :logo_dark, disguised)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['reason']).to eq('image_content')
      expect(body['errors']).to have_key('logo_dark')
      expect(page.reload.logo_dark.blob).to eq(generated)
      expect(source_of).to eq('generated')
    end

    it 'a gerada pelo motor de verdade é PNG que passa na conferência' do
      begin
        require 'image_processing/vips'
      rescue LoadError => e
        skip "libvips indisponível nesta máquina: #{e.class}"
      end
      allow(engine).to receive(:call).and_call_original
      logo = Tempfile.new(['logo', '.png'])
      logo.binmode
      logo.write(Vips::Image.black(80, 40).bandjoin([0, 0, 255]).cast(:uchar).copy(interpretation: :srgb)
                            .draw_rect([13, 35, 68, 255], 10, 10, 60, 20, fill: true).pngsave_buffer)
      logo.rewind

      upload(admin, :logo, Rack::Test::UploadedFile.new(logo.path, 'image/png'))

      expect(response).to have_http_status(:ok)
      expect(source_of).to eq('generated')
      expect(page.reload.logo_dark.content_type).to eq('image/png')
      expect(Crm::BookingV2::ImageFile.problem(page, :logo_dark)).to be_nil
    end

    it 'motor que devolvesse algo que não é PNG: a regra recusa, a logo fica e a página vai para a placa' do
      engine_returns('generated', 'isto não é um PNG')

      upload(admin, :logo)

      expect(response).to have_http_status(:ok)
      expect(page.reload.logo).to be_attached
      expect(page.logo_dark).not_to be_attached
      expect(source_of).to eq('plate')
    end

    it 'salvar a identidade: logo de fundo escuro que não passa é recusada e nada é salvo' do
      upload(admin, :logo)
      attach_unchecked(page, :logo_dark, svg)

      call(admin, :post, "#{base}/#{page.id}/save_identity")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['errors']).to have_key('logo_dark')
      expect(account.reload.booking_identity_logo).not_to be_attached
      expect(account.booking_identity_logo_dark).not_to be_attached
    end

    it 'usar a identidade: logo de fundo escuro salva que não passa não vai para a página; a página gera a dela' do
      upload(admin, :logo)
      call(admin, :post, "#{base}/#{page.id}/save_identity")
      attach_unchecked(account, :booking_identity_logo_dark, svg, filename: 'logo-fundo-escuro.png')
      other = create_booking_profile(account: account, host: world.host)

      call(admin, :post, "#{base}/#{other.id}/apply_identity")

      expect(response).to have_http_status(:ok)
      other.reload
      expect(other.logo.blob).to eq(page.reload.logo.blob)
      expect(other.logo_dark).to be_attached
      expect(other.logo_dark.blob).not_to eq(account.reload.booking_identity_logo_dark.blob)
      expect(Crm::BookingV2::ImageFile.problem(other, :logo_dark)).to be_nil
    end

    it 'enviar, tirar ou voltar para a gerada não manda desenhar a prévia do link, que não usa a logo de fundo escuro' do
      upload(admin, :logo)
      Redis::Alfred.delete(Crm::BookingV2::PreviewImage::Warmup.queued_key(page.id))

      expect do
        upload(admin, :logo_dark, file('sample.png'))
        call(admin, :delete, "#{base}/#{page.id}/logo_dark")
      end.not_to have_enqueued_job(Crm::BookingV2::PreviewImageWarmJob)
    ensure
      Redis::Alfred.delete(Crm::BookingV2::PreviewImage::Warmup.queued_key(page.id))
    end
  end
end
