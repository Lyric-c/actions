<script lang="ts">
	import { onMount } from 'svelte';
	import type { Linter } from 'harper.js';
	import { Editor } from 'harper-editor';
	import { createLinter } from '$lib/createLinter';

	let linter: Linter | null = null;

	let content = '';

	onMount(async () => {
		const params = new URLSearchParams(window.location.search);
		const initial = params.get('initialText');
		if (initial) content = initial;

		linter = await createLinter();
	});
</script>

<svelte:head>
	<title>Harper Editor</title>
</svelte:head>

<div class="page">
	{#if linter}
		<Editor
			{content}
			{linter}
			onChange={(text) => {
				content = text;
			}}
		/>
	{:else}
		<div class="loading">Loading Harper...</div>
	{/if}
</div>

<style>
	:global(html),
	:global(body) {
		margin: 0;
		width: 100%;
		height: 100%;
	}

	:global(body) {
		overflow: hidden;
	}

	:global(#svelte) {
		width: 100%;
		height: 100%;
	}

	.page {
		width: 100%;
		height: 100vh;
	}

	.loading {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 100%;
		height: 100%;
		font-family: system-ui, sans-serif;
		color: #666;
	}
</style>
