/// <reference types="vitest" />
import path from 'path';
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [vue(vueOptions), yaml()],
  resolve: {
    alias: { ...aliases, 'test-i18n': path.resolve('./vitest.i18n.js') },
  },
  test: {
    environment: 'jsdom',
    include: [
      'app/**/*.{test,spec}.?(c|m)[jt]s?(x)',
      // O gerador do mapa do Guia vive em scripts/ (#534) e tem teste próprio.
      'scripts/**/*.{test,spec}.?(c|m)[jt]s?(x)',
    ],
    coverage: {
      reporter: ['lcov', 'text'],
      include: ['app/**/*.js', 'app/**/*.vue'],
      exclude: [
        'app/**/*.@(spec|stories|routes).js',
        '**/specs/**/*',
        '**/i18n/**/*',
      ],
    },
    globals: true,
    outputFile: 'coverage/sonar-report.xml',
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
      },
    },
    server: {
      deps: {
        // Match the app's Vue alias inside composable dependencies as well. Otherwise
        // pnpm's secondary Vue copy can disconnect real dropdown refs in jsdom.
        inline: ['tinykeys', '@material/mwc-icon', /@vueuse\//, /vuex/],
      },
    },
    setupFiles: ['fake-indexeddb/auto', 'vitest.setup.js'],
    mockReset: true,
    clearMocks: true,
  },
});
