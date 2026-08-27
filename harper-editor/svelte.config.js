import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	extensions: ['.svelte', '.md'],
	preprocess: vitePreprocess(),
	kit: {
		prerender: {
			entries: [],
		},
		adapter: adapter({
			fallback: 'index.html',
		}),
	},
};

export default config;
