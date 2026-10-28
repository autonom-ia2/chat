require 'rails_helper'

# #2308, decisão 11: a recusa 401 de /custom_roles diz o motivo no corpo, no formato das outras recusas do controller
# ({ error:, message: }). O status e a regra não mudam; a tela de Funções guiadas mostra uma frase por código.
RSpec.describe 'Custom role refusal codes (#2308)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:builder_role) { create(:custom_role, account: account, permissions: %w[custom_role_manage contact_view]) }
  let!(:builder) do
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by!(account: account).update!(custom_role: builder_role)
    user
  end

  # A mensagem é comparada com o texto literal do en.yml, não com o I18n.t do próprio teste: se a chave sumir, os dois
  # lados virariam 'Translation missing' e o teste passaria.
  let(:messages) do
    {
      'feature_off' => 'Team roles are not available on this account right now.',
      'own_role' => 'Nobody changes their own role.',
      'out_of_reach' => "You can't give part of this role. Ask the administrator."
    }
  end

  # Rodada 6/7: todo 401 que o controller manda leva um código da lista. Lê o controller pelo parser do Ruby: cada
  # refuse(código, :unauthorized | 401) passa o código do Denied resgatado (pela variável que o próprio rescue declara),
  # um literal ou uma constante cujo valor está na lista; e nenhum render/head responde 401 por fora do refuse.
  # Rodada 8: o status vale em símbolo, número ou texto, com `status:` ou `:status =>`; render_unauthorized é sempre um
  # 401 por fora; e um refuse com o status numa variável não dá para ler, então também é apontado.
  let(:refusal_reader) do
    Class.new(Prism::Visitor) do
      attr_reader :refusals, :loose

      def initialize
        super
        @refusals = []
        @loose = []
        @denied_var = nil
      end

      # Dentro do rescue do Denied vale a variável que ele declara; um rescue de outra coisa com o mesmo nome a esconde.
      def visit_rescue_node(node)
        visit_all(node.exceptions)
        outer = @denied_var
        name = node.reference&.name
        denied = node.exceptions.any? { |exception| exception.slice == 'CustomRoles::GrantGuard::Denied' }
        @denied_var = denied ? name : (outer unless name == outer)
        visit(node.statements)
        @denied_var = outer
        visit(node.subsequent)
      end

      def visit_call_node(node)
        args = node.receiver.nil? ? node.arguments&.arguments.to_a : []
        if refusal_401?(node, args)
          @refusals << [node.slice, code_of(args.first)]
        elsif loose_401?(node, args)
          @loose << node.slice
        end
        super
      end

      private

      def loose_401?(node, args)
        return true if node.name == :render_unauthorized
        return unreadable_status?(args.last) if node.name == :refuse && args.size == 2

        %i[render head].include?(node.name) && args.any? { |arg| unauthorized?(arg) }
      end

      def unreadable_status?(node)
        [Prism::SymbolNode, Prism::IntegerNode, Prism::StringNode].none? { |kind| node.is_a?(kind) }
      end

      def refusal_401?(node, args)
        node.name == :refuse && args.size == 2 && unauthorized?(args.last)
      end

      def code_of(node)
        case node
        when Prism::CallNode then [:denied] if denied_code?(node)
        when Prism::StringNode then [:value, node.unescaped]
        when Prism::ConstantReadNode, Prism::ConstantPathNode then [:constant, node.name]
        end
      end

      def denied_code?(node)
        node.name == :code && node.receiver.is_a?(Prism::LocalVariableReadNode) && node.receiver.name == @denied_var
      end

      def unauthorized?(node)
        case node
        when Prism::SymbolNode, Prism::StringNode then %w[unauthorized 401].include?(node.unescaped)
        when Prism::IntegerNode then node.value == 401
        when Prism::KeywordHashNode, Prism::HashNode then node.elements.any? { |pair| status_pair?(pair) && unauthorized?(pair.value) }
        else false
        end
      end

      def status_pair?(pair)
        pair.is_a?(Prism::AssocNode) && pair.key.is_a?(Prism::SymbolNode) && pair.key.unescaped == 'status'
      end
    end
  end

  before { account.enable_features!('custom_roles') }

  def create_role(as:, permissions:)
    post "/api/v1/accounts/#{account.id}/custom_roles",
         params: { custom_role: { name: 'Nova', permissions: permissions } },
         headers: as.create_new_auth_token, as: :json
  end

  def update_role(role, as:)
    put "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}",
        params: { custom_role: { name: 'Outro nome' } },
        headers: as.create_new_auth_token, as: :json
  end

  def expect_refusal(code)
    expect(response).to have_http_status(:unauthorized)
    expect(Api::V1::Accounts::CustomRolesController::UNAUTHORIZED_CODES).to include(code)
    expect(response.parsed_body).to eq('error' => code, 'message' => messages.fetch(code))
  end

  # Rodada 6: todo código da lista tem mensagem nos arquivos de verdade (en e pt_BR), lidos do disco: o I18n cairia no
  # inglês e esconderia a falta do português.
  it 'has a message for every 401 code in the real en and pt_BR files' do
    codes = Api::V1::Accounts::CustomRolesController::UNAUTHORIZED_CODES

    expect(codes).to be_frozen
    %w[en pt_BR].each do |locale|
      file = YAML.load_file(Rails.root.join("config/locales/#{locale}.yml"))
      texts = file.dig(locale, 'errors', 'custom_role')
      codes.each { |code| expect(texts[code]).to be_present, "#{locale}: #{code}" }
    end
  end

  def listed_code?(controller, (kind, value))
    case kind
    when :denied then true
    when :value then controller::UNAUTHORIZED_CODES.include?(value)
    when :constant then controller.const_defined?(value) && controller::UNAUTHORIZED_CODES.include?(controller.const_get(value))
    else false
    end
  end

  def refusal_problems(source)
    parsed = Prism.parse(source)
    raise parsed.errors.map(&:message).join(', ') if parsed.failure?

    reader = refusal_reader.new
    parsed.value.accept(reader)
    unlisted = reader.refusals.reject { |_, code| listed_code?(Api::V1::Accounts::CustomRolesController, code) }
    { refusals: reader.refusals.size, problems: unlisted.map(&:first) + reader.loose }
  end

  it 'only sends listed codes in its 401 refusals' do
    controller = Api::V1::Accounts::CustomRolesController
    source = Rails.root.join('enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb').read
    result = refusal_problems(source)

    expect(controller::UNAUTHORIZED_CODES).to include(*CustomRoles::GrantGuard::CODES)
    expect(result[:refusals]).to be >= 4
    expect(result[:problems]).to be_empty
  end

  # A leitura acima pega o que deve pegar e deixa passar o que vale (rodada 7): cada trecho dentro de um método.
  {
    'refuse(e.code, :unauthorized) with e from another rescue' =>
      ['x; rescue StandardError => e; refuse(e.code, :unauthorized)', false],
    'a code outside the list' => ["refuse('nope', 401)", false],
    'render with status: :unauthorized' => ['render json: {}, status: :unauthorized', false],
    'head 401' => ['head 401', false],
    'render_unauthorized' => ["render_unauthorized('no')", false],
    'render with status as text' => ["render json: {}, status: 'unauthorized'", false],
    'render with the hash-rocket status' => ['render json: {}, :status => :unauthorized', false],
    'refuse with the status in a variable' => ["refuse('x', variavel)", false],
    'refuse with a status other than 401' => ["refuse('changed_meanwhile', :conflict)", true],
    'the Denied code under another variable name' =>
      ['x; rescue CustomRoles::GrantGuard::Denied => error; refuse(error.code, :unauthorized)', true],
    'a listed constant' => ['refuse(FEATURE_OFF, :unauthorized)', true],
    'a listed constant through self.class' => ['refuse(self.class::FEATURE_OFF, :unauthorized)', true],
    'a listed literal' => ["refuse('feature_off', 401)", true]
  }.each do |label, (body, accepted)|
    it "#{accepted ? 'accepts' : 'flags'} #{label}" do
      result = refusal_problems("def sample\n#{body}\nend")

      expect(result[:problems].empty?).to be(accepted)
    end
  end

  # Controle positivo: o GrantGuard não recusa tudo; dentro do alcance, quem monta cria.
  it 'lets the builder create a role within reach' do
    expect { create_role(as: builder, permissions: %w[contact_view]) }.to change(CustomRole, :count).by(1)
    expect(response).to have_http_status(:ok)
  end

  it "answers 'feature_off' when the account does not have custom roles, and logs the refusal" do
    account.disable_features!('custom_roles')
    allow(Rails.logger).to receive(:info).and_call_original

    expect { create_role(as: admin, permissions: %w[contact_view]) }.not_to change(CustomRole, :count)
    expect_refusal('feature_off')
    expect(Rails.logger).to have_received(:info).with('custom_roles: recusa feature_off (recurso desligado na conta)')
  end

  it "answers 'feature_off' to the builder too when the account does not have custom roles" do
    account.disable_features!('custom_roles')

    get "/api/v1/accounts/#{account.id}/custom_roles", headers: builder.create_new_auth_token, as: :json

    expect_refusal('feature_off')
  end

  it "answers 'own_role' when someone who is not an administrator changes the role they hold" do
    update_role(builder_role, as: builder)

    expect_refusal('own_role')
    expect(builder_role.reload.name).not_to eq('Outro nome')
  end

  it "answers 'out_of_reach' for keys the giver does not hold and for a role above them" do
    expect { create_role(as: builder, permissions: %w[contact_view crm_export]) }.not_to change(CustomRole, :count)
    expect_refusal('out_of_reach')

    above = create(:custom_role, account: account, name: 'Financeiro', permissions: %w[financial_view])
    update_role(above, as: builder)
    expect_refusal('out_of_reach')
    expect(above.reload.name).to eq('Financeiro')

    delete "/api/v1/accounts/#{account.id}/custom_roles/#{above.id}", headers: builder.create_new_auth_token, as: :json
    expect_refusal('out_of_reach')
    expect(CustomRole.exists?(above.id)).to be(true)
  end

  it 'keeps the generic refusal, without a code, for whoever cannot build roles' do
    plain_agent = create(:user, account: account, role: :agent)

    create_role(as: plain_agent, permissions: %w[contact_view])

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
    expect(response.parsed_body).not_to have_key('message')
  end

  # Quem não gerencia funções não fica sabendo do plano: com o recurso desligado, a recusa continua a genérica.
  it 'keeps the generic refusal for whoever cannot build roles when the account does not have custom roles' do
    plain_agent = create(:user, account: account, role: :agent)
    account.disable_features!('custom_roles')

    get "/api/v1/accounts/#{account.id}/custom_roles", headers: plain_agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
  end
end
