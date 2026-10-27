"""Export validated scores, or redraw from the public summary with --scores.

uv run --with matplotlib python _benchmarks/publish_das_scores.py \
    --scores assets/data/flame-vllm-das-20261027.json
"""
import argparse
import json
import math
from pathlib import Path
import statistics


def export(results):
    lru = json.loads((results / 'capacity16lru/validated-capacity-summary.json').read_text())
    random = json.loads((results / 'capacity16/validated-capacity-summary.json').read_text())
    neutral = json.loads((results / 'gpu-evidence/runs/comparison-r1/validated-summary.json').read_text())
    for name, count in (('capacity16lru', 12), ('capacity16', 18)):
        validation = json.loads((results / name / 'local-validation.json').read_text())
        assert validation['valid'] and validation['gpu_summary_matches_local']
        assert validation['completed_cases'] == count
    assert lru['valid'] and random['valid'] and neutral['valid']

    def confirmation(source, flame):
        comparison = source['comparisons'][flame + '_over_vllm-round-robin']
        pairs = []
        arms = {}
        for arm in (flame, 'vllm-round-robin'):
            cases = [c for c in source['cases'] if c['phase'] == 'confirmation' and c['arm'] == arm]
            assert len(cases) == 6
            assert all(c['requests'] == 192 for c in cases)
            rates = [c['requests_s'] for c in cases]
            assert math.isclose(statistics.mean(rates), source['arms'][arm]['requests_s'], rel_tol=1e-12)
            assert math.isclose(statistics.mean(c['cached_token_fraction'] for c in cases), source['arms'][arm]['cached_token_fraction'], rel_tol=1e-12)
            arms[arm] = dict(source['arms'][arm], requests_s_range=[min(rates), max(rates)], runs=6)
        for index in range(6):
            rows = {}
            for arm in (flame, 'vllm-round-robin'):
                c = next(c for c in source['cases'] if c['phase'] == 'confirmation' and c['repetition'] == index and c['arm'] == arm)
                rows[arm] = {key: c[key] for key in ('requests_s', 'seconds', 'requests', 'input_tokens', 'cached_input_tokens', 'uncached_input_tokens', 'cached_token_fraction')}
                rows[arm]['requests_per_gpu'] = sorted(c['requests_per_gpu'].values())
            ratio = rows[flame]['requests_s'] / rows['vllm-round-robin']['requests_s']
            assert math.isclose(ratio, comparison['paired_ratios'][index], rel_tol=1e-12)
            pairs.append(dict(repetition=index, arms=rows, throughput_ratio=ratio))
        assert math.isclose(math.exp(statistics.mean(math.log(p['throughput_ratio']) for p in pairs)), comparison['geometric_mean_ratio'], rel_tol=1e-12)
        return dict(arms=arms, comparison=comparison, pairs=pairs, declaration=source['declaration'])

    provenance = {}
    for name in ('capacity16', 'capacity16lru'):
        receipt = json.loads((results / name / 'archive-receipt.json').read_text())
        provenance[name] = {key: receipt[key] for key in ('archive_sha256', 'archive_bytes', 'completed_cases', 'baseline_source_commit', 'candidate_sources')}
    return dict(
        updated='2026-10-27', feature='Flame data-aware scheduling (DAS)',
        scope='Controlled low-arrival synthetic document-reuse diagnostic; not maximum serving capacity or MLPerf.',
        runtime=dict(model='unsloth/Meta-Llama-3.1-8B-Instruct', model_revision='a2856192dd7c25b842431f39c179a6c2c2f627d1',
                     vllm='0.28.0', torch='2.13.0+cu130', gpu_model='NVIDIA B200', gpu_count=2,
                     cpu_limit=20, tensor_parallel_size=1, dtype='bfloat16', eager=True,
                     attention_backend='TRITON_ATTN', prefix_caching=True, async_scheduling=False,
                     gpu_memory_utilization=0.45, max_num_seqs=64, max_num_batched_tokens=8192,
                     max_model_len=16384, kv_blocks_per_gpu=4096, block_size=16,
                     kv_capacity_tokens_per_gpu=65536, output_tokens_per_request=16,
                     flame_session_storage='none', flame_object_cache_storage='filesystem',
                     flame_object_cache_budget='1G', instrumented_kv_journal=True),
        lru_confirmation=confirmation(lru, 'flame-das-lru-job'),
        random_confirmation=confirmation(random, 'flame-das-random-job'),
        descriptive_pilots=[{key: c[key] for key in ('arm', 'requests_s', 'seconds', 'cached_token_fraction')} for c in random['cases'] if c['phase'] == 'pilot'],
        earlier_8k_diagnostic=dict(scope=neutral['scope'], comparisons=neutral['comparisons'], confirmation_arms=neutral['confirmation_arms']),
        provenance=provenance,
        experimental_candidate=True, production_candidate_deployed=False,
        raw_archive_availability='Retained locally; this public file contains curated scores and configuration, not raw request/journal archives.',
    )


def plot(data, directory):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt

    primary = data['lru_confirmation']
    comparison = primary['comparison']
    gain = (comparison['geometric_mean_ratio'] - 1) * 100
    low, high = [(v - 1) * 100 for v in comparison['percentile_bootstrap_95_ci']]
    plt.rcParams.update({'font.size': 10, 'svg.fonttype': 'none',
                         'axes.spines.top': False, 'axes.spines.right': False})
    fig, (left, right) = plt.subplots(1, 2, figsize=(12.4, 5.7), gridspec_kw={'width_ratios': [1, 1.1]})
    for y, arm, label, color in (
        (1, 'vllm-round-robin', 'Native vLLM\nround-robin', '#586777'),
        (0, 'flame-das-lru-job', 'Flame\nDAS + LRU', '#db7547'),
    ):
        value = primary['arms'][arm]
        mean = value['requests_s']
        minimum, maximum = value['requests_s_range']
        left.barh(y, mean, height=.5, color=color)
        left.errorbar(mean, y, xerr=[[mean - minimum], [maximum - mean]], fmt='none', ecolor='#202b35', capsize=4)
        left.text(maximum + .09, y, f"{mean:.2f}", va='center', weight='bold', fontsize=12)
        left.text(.12, y - .34, f"Cached input: {value['cached_token_fraction']:.2%}", color='#52606a', va='center', fontsize=9)
    left.set_yticks([0, 1], ['Flame\nDAS + LRU', 'Native vLLM\nround-robin'])
    left.set_ylim(-.65, 1.65)
    left.set_xlim(0, 4.65)
    left.set_title('Completion throughput', pad=16)
    left.set_xlabel('Requests / second · mean and observed range, n=6')
    left.grid(axis='x', alpha=.17)
    left.set_axisbelow(True)
    left.spines['left'].set_visible(False)
    left.tick_params(axis='y', length=0)

    ratios = [(p['throughput_ratio'] - 1) * 100 for p in primary['pairs']]
    right.scatter(ratios, range(6), s=40, color='#db7547', zorder=3)
    right.errorbar(gain, 6.5, xerr=[[gain - low], [high - gain]], fmt='D', color='#202b35', capsize=5)
    right.axhline(5.75, color='#c6cdd3', linewidth=.8)
    right.set_yticks(list(range(6)) + [6.5], [f'Pair {i + 1}' for i in range(6)] + ['Paired estimate'])
    right.invert_yaxis()
    right.set_xlim(0, 22)
    right.set_title(f'+{gain:.1f}% throughput\n95% bootstrap interval: +{low:.1f}% to +{high:.1f}%', pad=14)
    right.set_xlabel('Flame gain over round-robin vLLM (%)')
    right.grid(axis='x', alpha=.17)
    right.set_axisbelow(True)
    right.spines['left'].set_visible(False)
    right.tick_params(axis='y', length=0)

    fig.suptitle("Flame data-aware scheduling (DAS): reusing GPU-resident document prefixes", fontsize=14, y=.98)
    fig.text(.035, .065, 'Two B200 GPUs · synthetic 16K documents · 65,536 KV tokens/GPU · one active four-request job · 16 output tokens/request.', fontsize=8.5, color='#52606a')
    fig.text(.035, .025, 'Six fresh paired runs; 192 measured requests/case. Native cache-aware controls are reported separately as single pilots in the article.', fontsize=8.5, color='#52606a')
    fig.tight_layout(rect=(0, .13, 1, .91), w_pad=2.5)
    directory.mkdir(parents=True, exist_ok=True)
    for extension in ('svg', 'png'):
        output = directory / ('das-kv-placement.' + extension)
        fig.savefig(output, dpi=180, facecolor='white')
        if extension == 'svg':
            output.write_text('\n'.join(line.rstrip() for line in output.read_text().splitlines()) + '\n')
    plt.close(fig)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--results', type=Path, default=Path('_benchmarks/results/das-kv-20261027'))
    parser.add_argument('--site', type=Path, default=Path('.'))
    parser.add_argument('--scores', type=Path, help='Redraw from a previously exported public summary')
    args = parser.parse_args()
    data = json.loads(args.scores.read_text()) if args.scores else export(args.results)
    destination = args.site / 'assets/data/flame-vllm-das-20261027.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(data, indent=2) + '\n')
    plot(data, args.site / 'assets/images/serving-benchmark')
    print(json.dumps(dict(score_summary=str(destination), paired_gain=data['lru_confirmation']['comparison']['geometric_mean_ratio'])))
