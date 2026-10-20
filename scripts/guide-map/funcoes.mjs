// Toda tela do painel tem decisão sobre funções personalizadas (#1157).
//
// Cada tela nova escolhia a permissão na hora, e nada pedia a chave da função
// personalizada. Assim Anúncios Meta, Modelos do WhatsApp e outras telas nasceram só
// para administrador, e a função com Campanhas liberado não as via. A regra agora: a
// rota aceita uma chave de função, ou está em adminOnlyRoutes.json com o motivo.
// Lê o roteador com o mesmo carregador do mapa do Guia.
import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';

const raiz = process.cwd();
const CATALOGO = 'enterprise/app/models/custom_role.rb';
const EXCECOES =
  'app/javascript/dashboard/routes/dashboard/settings/customRoles/adminOnlyRoutes.json';

// As chaves de `CustomRole::PERMISSIONS`, lidas do próprio modelo.
export const lerChaves = rubi => {
  const [, depois] = rubi.split('PERMISSIONS = %w[');
  if (!depois) throw new Error(`${CATALOGO}: não achei PERMISSIONS = %w[`);
  // Uma chave por linha no modelo.
  return depois
    .split(']')[0]
    .split('\n')
    .map(linha => linha.trim())
    .filter(Boolean);
};

const casa = (entrada, nome) =>
  entrada === nome || (entrada.endsWith('_') && nome.startsWith(entrada));

export const conferir = ({ rotas, chaves, excecoes }) => {
  const aceitas = new Set([...chaves, 'custom_role']);
  const entradas = Object.keys(excecoes).filter(chave => chave !== '_leia');
  const abreParaFuncao = rota => rota.papeis.some(p => aceitas.has(p));
  const comPapeis = rotas.filter(rota => rota.papeis?.length);

  const semDecisao = comPapeis
    .filter(rota => !abreParaFuncao(rota))
    .filter(rota => !entradas.some(entrada => casa(entrada, rota.nome)))
    .map(rota => rota.nome);

  // Entrada exata cuja rota já abre para função, ou entrada que não acha rota: a lista
  // mente e precisa sair — senão ela esconde a próxima tela fechada.
  const sobrando = entradas.filter(entrada => {
    const alvo = comPapeis.filter(rota => casa(entrada, rota.nome));
    if (!alvo.length) return true;
    return !entrada.endsWith('_') && alvo.every(abreParaFuncao);
  });

  return { semDecisao, sobrando };
};

const main = async () => {
  // Importado aqui: o carregador sobe o Vite, e o teste da regra roda sem ele.
  const { lerRotas } = await import('./build.mjs');
  const chaves = lerChaves(
    fs.readFileSync(path.resolve(raiz, CATALOGO), 'utf8')
  );
  const excecoes = JSON.parse(
    fs.readFileSync(path.resolve(raiz, EXCECOES), 'utf8')
  );
  const { semDecisao, sobrando } = conferir({
    rotas: await lerRotas(),
    chaves,
    excecoes,
  });

  semDecisao.forEach(nome =>
    console.error(
      `Tela sem decisão de função personalizada: \`${nome}\`. Ponha uma chave de CustomRole::PERMISSIONS em meta.permissions, ou declare a tela em ${EXCECOES} com o motivo.`
    )
  );
  sobrando.forEach(entrada =>
    console.error(
      `\`${entrada}\` está em ${EXCECOES}, mas a tela já abre para função ou não existe mais. Tire da lista.`
    )
  );
  if (semDecisao.length || sobrando.length) process.exit(1);
  console.log('Toda tela do painel tem decisão sobre funções personalizadas.');
};

if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
