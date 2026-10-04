require 'rails_helper'
require 'open3'

# AutomationRule e AutomationRuleSchema se referem um ao outro. Se o model lesse o esquema ao carregar, quem
# carregasse o esquema primeiro (MacroSchema, o Guia) quebrava com NameError — e só aparecia conforme a ordem
# em que os arquivos eram carregados (#963). Cada classe é carregada primeiro num processo novo, a única forma
# de reproduzir a ordem de carga de verdade.
RSpec.describe AutomationRule do
  %w[AutomationRuleSchema MacroSchema AutomationRule Macro].each do |classe|
    it "carrega #{classe} primeiro, num processo novo, sem ciclo de carga" do
      codigo = "#{classe}; AutomationRule; AutomationRuleSchema::EVENTO; AutomationRuleSchema::ATRASO; puts 'carregou'"
      saida, status = Bundler.with_original_env do
        Open3.capture2e({ 'RAILS_ENV' => 'test', 'DISABLE_SPRING' => '1' },
                        Gem.ruby, Rails.root.join('bin/rails').to_s, 'runner', codigo, chdir: Rails.root.to_s)
      end

      expect(status.success?).to be(true), saida.lines.last(15).join
      expect(saida).to include('carregou')
    end
  end
end
