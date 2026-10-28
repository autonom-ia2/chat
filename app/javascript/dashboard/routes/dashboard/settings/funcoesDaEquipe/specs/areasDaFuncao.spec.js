import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  MODULES,
  PRESETS,
  getLevel,
  moduleByKey,
  setLevel,
} from '../../customRoles/permissionMatrix';
import {
  CONDICIONAL,
  DENTRO_DE,
  DONO_DAS_CHAVES,
  LINHAS,
  RECOLHIDA,
  SO_ADMIN,
  areasDaRecolhida,
  gruposDoCuidado,
  resumoDaRecolhida,
  travaDoNivel,
} from '../areasDaFuncao';
import { motivoDaTrava } from '../motivoDaTrava';
import { ADMIN, CARLA, CARLA_SEM_DISPARO } from './quemMonta';

// #2308, especificação 6 e 7: o mapa fechado (24/24 módulos, 57/57 chaves), a recolhida e o Cuidado em três grupos.
const permissoesDoServidor = () => {
  const fonte = readFileSync(
    resolve(process.cwd(), 'enterprise/app/models/custom_role.rb'),
    'utf8'
  );
  const inicio =
    fonte.indexOf('PERMISSIONS = %w[') + 'PERMISSIONS = %w['.length;
  return fonte
    .slice(inicio, fonte.indexOf('].freeze', inicio))
    .split('\n')
    .flatMap(linha => linha.trim().split(' '))
    .filter(Boolean);
};

describe('mapa das áreas e chaves', () => {
  it('24/24 módulos têm lugar, sem repetir', () => {
    const lugares = [
      ...LINHAS,
      ...Object.keys(DENTRO_DE),
      ...RECOLHIDA,
      ...CONDICIONAL,
      ...SO_ADMIN,
    ];
    expect(lugares).toHaveLength(24);
    expect(new Set(lugares)).toEqual(new Set(MODULES.map(m => m.key)));
  });

  it('57/57 chaves de CustomRole::PERMISSIONS têm dono, sem repetir', () => {
    const donas = Object.values(DONO_DAS_CHAVES).flat();
    const servidor = permissoesDoServidor();

    expect(servidor).toHaveLength(57);
    expect(donas).toHaveLength(57);
    expect(new Set(donas)).toEqual(new Set(servidor));
  });
});

describe('recolhida de Ajustes (Carla + Atendente)', () => {
  const atendente = PRESETS.AGENT();

  it('título e estado: duas primeiras + "mais 11"; só olha a Central de Ajuda', () => {
    const areas = areasDaRecolhida({
      giver: CARLA,
      permissions: atendente,
      inicial: atendente,
      comCotacoes: false,
    });
    expect(areas.subiram).toEqual([]);
    expect(areas.cadeado.map(m => m.key)).toEqual(SO_ADMIN);
    expect(resumoDaRecolhida(areas.recolhidas, atendente)).toEqual({
      primeiras: ['REPORTS', 'DESEMPENHO'],
      mais: 11,
      olha: ['KNOWLEDGE_BASE'],
      mexe: [],
    });
  });

  it('a área mudada sobe e o título se refaz', () => {
    const comRelatorios = setLevel(moduleByKey('REPORTS'), 'view', atendente);
    const areas = areasDaRecolhida({
      giver: CARLA,
      permissions: comRelatorios,
      inicial: atendente,
      comCotacoes: false,
    });
    expect(areas.subiram.map(m => m.key)).toEqual(['REPORTS']);
    expect(resumoDaRecolhida(areas.recolhidas, comRelatorios)).toMatchObject({
      primeiras: ['DESEMPENHO', 'CANNED_RESPONSES'],
      mais: 10,
    });
  });

  it('para o administrador, Integrações, Equipe e Financeiro entram como as outras', () => {
    const areas = areasDaRecolhida({
      giver: ADMIN,
      permissions: atendente,
      inicial: atendente,
      comCotacoes: true,
    });
    expect(areas.cadeado).toEqual([]);
    expect(areas.recolhidas).toHaveLength(17);
  });

  it('Anúncios: "Pode mexer" com cadeado de delegação; Cotações: as duas com MISSING', () => {
    const anuncios = moduleByKey('META_ADS');
    const cotacoes = moduleByKey('INSURANCE');
    expect(travaDoNivel(CARLA, anuncios, 'view')).toBeNull();
    expect(travaDoNivel(CARLA, anuncios, 'manage')).toBe('DELEGATION');
    expect(travaDoNivel(CARLA, cotacoes, 'view')).toBe('MISSING');
    expect(travaDoNivel(CARLA, cotacoes, 'manage')).toBe('MISSING');
    expect(travaDoNivel(ADMIN, anuncios, 'manage')).toBeNull();
  });
});

describe('Cuidado em três grupos', () => {
  const chaves = itens => itens.map(item => item.chave);

  it('Carla + Atendente = tabela da especificação 7.2', () => {
    const grupos = gruposDoCuidado(CARLA, PRESETS.AGENT());

    expect(chaves(grupos.ligaJunto)).toEqual([
      'contact_delete',
      'campaign_send',
    ]);
    expect(chaves(grupos.ligaAgora)).toEqual([
      'contact_export',
      'conversation_message_delete',
      'crm_manage_ai',
    ]);
    expect(grupos.naoPode).toEqual([
      expect.objectContaining({ chave: 'crm_export', motivo: 'MISSING' }),
      expect.objectContaining({
        chave: 'crm_metas_manage',
        motivo: 'DELEGATION',
      }),
    ]);
  });

  // (a) e (b) não se sobrepõem: (b) é "a área ainda não está em manage", (a) é "já está". Por isso a ordem dos testes
  // não importa; o que importa é que cada chave cai em um grupo só, e que a mesma chave troca de grupo com a área.
  it('cada chave ligável cai em um grupo só: "liga junto" e "liga agora" são disjuntos', () => {
    expect(motivoDaTrava(CARLA, 'contact_delete')).toBeNull();
    [PRESETS.AGENT(), PRESETS.SDR(), PRESETS.MARKETING()].forEach(funcao => {
      const { ligaJunto, ligaAgora } = gruposDoCuidado(CARLA, funcao);
      const junto = chaves(ligaJunto);
      expect(chaves(ligaAgora).filter(chave => junto.includes(chave))).toEqual(
        []
      );
    });
    expect(chaves(gruposDoCuidado(CARLA, PRESETS.AGENT()).ligaJunto)).toContain(
      'contact_delete'
    );
    expect(
      chaves(gruposDoCuidado(CARLA, PRESETS.AGENT()).ligaAgora)
    ).not.toContain('contact_delete');
  });

  it('com a área já em manage, a mesma chave liga agora', () => {
    const comContatos = setLevel(
      moduleByKey('CONTACTS'),
      'manage',
      PRESETS.AGENT()
    );
    expect(chaves(gruposDoCuidado(CARLA, comContatos).ligaAgora)).toContain(
      'contact_delete'
    );
    expect(getLevel(moduleByKey('CONTACTS'), comContatos)).toBe('manage');
  });

  it('sem disparar campanhas, a Carla vê 3 coisas no cadeado', () => {
    const grupos = gruposDoCuidado(CARLA_SEM_DISPARO, PRESETS.AGENT());
    expect(chaves(grupos.naoPode)).toEqual([
      'campaign_send',
      'crm_export',
      'crm_metas_manage',
    ]);
  });

  it('o administrador liga tudo; quem não atende conversas não vê "Apagar mensagens"', () => {
    const grupos = gruposDoCuidado(ADMIN, PRESETS.MARKETING());
    expect(grupos.naoPode).toEqual([]);
    expect([
      ...chaves(grupos.ligaJunto),
      ...chaves(grupos.ligaAgora),
    ]).not.toContain('conversation_message_delete');
  });
});
