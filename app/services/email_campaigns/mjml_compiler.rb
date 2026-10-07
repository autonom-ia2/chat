require 'open3'

# Compiles MJML to HTML with mjml-browser under STRICT validation (lib/tasks/support/mjml_compile.js),
# the same compiler the editor uses. Needs Node and the frontend dependencies, so it runs at build
# time (compile rake task) and in CI (library quality gate) — never in the production image.
class EmailCampaigns::MjmlCompiler
  SCRIPT = Rails.root.join('lib/tasks/support/mjml_compile.js').freeze

  Result = Struct.new(:html, :errors) do
    def valid?
      errors.empty? && html.present?
    end
  end

  def self.call(mjml)
    output, error, status = Open3.capture3('node', SCRIPT.to_s, stdin_data: mjml.to_s, chdir: Rails.root.to_s)
    raise "mjml-browser unavailable (#{error.bytesize} diagnostic bytes)" unless status.success?

    parsed = JSON.parse(output)
    Result.new(parsed.fetch('html'), parsed.fetch('errors'))
  end
end
