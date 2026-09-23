// Central de Ajuda "Plataforma" — junta num roteiro único os prints pedidos nos artigos.
//
// Cada artigo em lib/central_de_ajuda/<cap>/*.md pede um print de duas formas, que
// precisam andar juntas (kit-do-escritor.md, seção 8):
//   no texto:  ![PRINT 02.04-a: legenda](prints/02.04-a.png)
//   no fim:    <!-- PRINT 02.04-a
//              rota: ...
//              estado: ...
//              destaque: ...
//              recorte: ...
//              -->
// O roteiro sai em docs/central-de-ajuda/prints/roteiro.json e é a lista que o script de
// captura percorre. Especificação de print que não aparece no texto é só uma ideia
// guardada: fica de fora do roteiro, mas é listada.
//
// Uso: node scripts/central-de-ajuda/roteiro-prints.mjs [--check]
//   --check falha se algum print do texto não tiver especificação (ou o contrário).

import { readdirSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = new URL('../../', import.meta.url).pathname;
const ARTIGOS = join(ROOT, 'lib/central_de_ajuda');
const SAIDA = join(ROOT, 'docs/central-de-ajuda/prints/roteiro.json');
const CAMPOS = ['rota', 'estado', 'destaque', 'recorte'];

const arquivos = () =>
  readdirSync(ARTIGOS, { withFileTypes: true })
    .filter(dir => dir.isDirectory())
    .flatMap(dir =>
      readdirSync(join(ARTIGOS, dir.name))
        .filter(nome => nome.endsWith('.md'))
        .map(nome => join(ARTIGOS, dir.name, nome))
    )
    .sort();

// ![PRINT 02.04-a: legenda](prints/02.04-a.png) -> { id, legenda }
const printsDoTexto = texto =>
  texto
    .split('\n')
    .filter(linha => linha.startsWith('![PRINT '))
    .map(linha => {
      const corpo = linha.slice('![PRINT '.length, linha.indexOf(']('));
      const doisPontos = corpo.indexOf(':');
      return {
        id: corpo.slice(0, doisPontos).trim(),
        legenda: corpo.slice(doisPontos + 1).trim(),
      };
    });

// <!-- PRINT 02.04-a ... --> -> { id, rota, estado, destaque, recorte }
const especificacoes = texto =>
  texto
    .split('<!-- PRINT ')
    .slice(1)
    .map(bloco => {
      const [cabeca, ...linhas] = bloco.slice(0, bloco.indexOf('-->')).split('\n');
      const spec = { id: cabeca.trim().split(' ')[0] };
      linhas.forEach(linha => {
        const doisPontos = linha.indexOf(':');
        const campo = linha.slice(0, doisPontos).trim();
        if (CAMPOS.includes(campo)) spec[campo] = linha.slice(doisPontos + 1).trim();
      });
      return spec;
    });

const roteiro = [];
const problemas = [];
const guardados = [];

arquivos().forEach(caminho => {
  const texto = readFileSync(caminho, 'utf8');
  const artigo = caminho.slice(ROOT.length);
  const noTexto = printsDoTexto(texto);
  const specs = especificacoes(texto);

  noTexto.forEach(({ id, legenda }) => {
    const spec = specs.find(s => s.id === id);
    if (!spec) {
      problemas.push(`${artigo}: o print ${id} está no texto e não tem especificação`);
      return;
    }
    const faltam = CAMPOS.filter(campo => !spec[campo]);
    if (faltam.length) problemas.push(`${artigo}: o print ${id} não diz ${faltam.join(', ')}`);
    roteiro.push({ ...spec, legenda, artigo, arquivo: `prints/${id}.png` });
  });

  specs
    .filter(spec => !noTexto.some(p => p.id === spec.id))
    .forEach(spec => guardados.push(`${artigo}: ${spec.id}`));
});

if (process.argv.includes('--check')) {
  problemas.forEach(p => console.error(p));
  process.exit(problemas.length ? 1 : 0);
}

mkdirSync(join(ROOT, 'docs/central-de-ajuda/prints'), { recursive: true });
writeFileSync(SAIDA, `${JSON.stringify(roteiro, null, 2)}\n`);
console.log(`${roteiro.length} prints no roteiro -> ${SAIDA.slice(ROOT.length)}`);
guardados.forEach(g => console.log(`guardado (fora do texto): ${g}`));
problemas.forEach(p => console.error(`PROBLEMA: ${p}`));
process.exit(problemas.length ? 1 : 0);
