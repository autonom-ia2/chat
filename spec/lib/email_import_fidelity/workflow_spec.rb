require 'rails_helper'

# O relatório de fidelidade (#1099, entrega D) roda no PR que muda a saída do importador. A saída não é só da pasta do
# importador: o canonicalizador do MJML, o rodapé travado e o compilador também a mudam, e uma mudança só neles tem de
# rodar o relatório.
RSpec.describe 'Email import fidelity workflow' do # rubocop:disable RSpec/DescribeClass
  let(:paths) do
    workflow = YAML.safe_load(Rails.root.join('.github/workflows/email-import-fidelity.yml').read, aliases: true)
    workflow.fetch(true).fetch('pull_request').fetch('paths')
  end

  it 'runs for every file that changes what an import produces' do
    expect(paths).to include('app/services/email_campaigns/import/**', 'app/services/email_campaigns/mjml_canonicalizer.rb',
                             'app/services/email_campaigns/locked_footer.rb', 'app/services/email_campaigns/mjml_compiler.rb')
    expect(paths).to all(satisfy { |path| path.end_with?('**') || Rails.root.join(path).exist? })
  end
end
