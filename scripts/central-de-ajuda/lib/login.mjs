// Login local sem expor token: o link de SSO nasce e morre dentro do
// `rails runner` — o Node nunca vê o valor, só o caminho do arquivo html
// que o próprio Ruby escreveu.

import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import {
  writeFileSync,
  unlinkSync,
  existsSync,
  mkdtempSync,
  rmSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const RAIZ_REPO = new URL('../../../', import.meta.url).pathname;

function rodarRailsRunner(codigoRuby) {
  return new Promise((resolve, reject) => {
    const pastaTmp = mkdtempSync(join(tmpdir(), 'gravar-trajeto-rb-'));
    const arquivoRb = join(pastaTmp, 'script.rb');
    writeFileSync(arquivoRb, codigoRuby);

    // eval do rbenv precisa rodar no mesmo shell do bundle exec, por isso
    // tudo vai como um único comando de shell.
    const comando = [
      'eval "$(rbenv init -)"',
      `SSL_CERT_FILE=/etc/ssl/cert.pem bundle exec rails runner -e development ${JSON.stringify(arquivoRb)}`,
    ].join(' && ');

    const processo = spawn('bash', ['-lc', comando], { cwd: RAIZ_REPO });
    let saida = '';
    let erro = '';
    processo.stdout.on('data', d => {
      saida += d.toString();
    });
    processo.stderr.on('data', d => {
      erro += d.toString();
    });
    processo.on('close', codigo => {
      rmSync(pastaTmp, { recursive: true, force: true });
      if (codigo !== 0) {
        reject(new Error(`rails runner falhou (código ${codigo}):\n${erro}`));
      } else {
        resolve(saida);
      }
    });
  });
}

/**
 * Roda um trecho de Ruby de preparação (não sensível) via rails runner —
 * usado pelos roteiros para resetar estado antes de gravar.
 */
export async function rodarRails(codigoRuby) {
  return rodarRailsRunner(codigoRuby);
}

/**
 * Gera o link de SSO da conta/usuária pedidas e grava um html de redirect
 * em public/__entrar_<hex>.html. O link nunca passa pelo stdout do Node:
 * o próprio Ruby escreve o arquivo.
 */
export async function criarLoginHtml({ contaId, usuarioNome, baseUrl }) {
  const hex = randomBytes(16).toString('hex');
  const nomeArquivo = `__entrar_${hex}.html`;
  const caminhoAbsoluto = join(RAIZ_REPO, 'public', nomeArquivo);

  const codigoRuby = `
conta = Account.find(${JSON.stringify(contaId)})
usuaria = conta.users.find_by(name: ${JSON.stringify(usuarioNome)})
raise "usuária #{${JSON.stringify(usuarioNome)}} não encontrada na conta #{conta.id}" unless usuaria

# Cada gravação abre uma sessão nova e a mata na marra (kill do Chrome), sem
# logout — rodar o script várias vezes seguidas (o objetivo do "de novo
# quando a tela mudar") ia acabar batendo no limite de sessões simultâneas
# do usuário de teste e travando o login num 409. Zera antes de cada gravação.
usuaria.user_sessions.destroy_all
usuaria.update!(tokens: {})

link = usuaria.generate_sso_link
link = ${JSON.stringify(baseUrl)} + link unless link.start_with?("http")

html = "<!doctype html><meta charset=\\"utf-8\\"><script>location.replace(" + link.to_json + ")</script>"
File.write(${JSON.stringify(caminhoAbsoluto)}, html)
puts "login-html-ok"
`;

  const saida = await rodarRailsRunner(codigoRuby);
  if (!saida.includes('login-html-ok') || !existsSync(caminhoAbsoluto)) {
    throw new Error(
      'Falha ao gerar o html de login local (ver saída do rails runner acima)'
    );
  }
  return { caminhoAbsoluto, nomeArquivo, urlFile: `file://${caminhoAbsoluto}` };
}

export function apagarLoginHtml(caminhoAbsoluto) {
  if (existsSync(caminhoAbsoluto)) unlinkSync(caminhoAbsoluto);
}
