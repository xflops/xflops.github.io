"""Draw the current measured startup and warm calls without historical cases."""
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

data = json.loads(Path('assets/data/hermes-flamepy-performance-20261028.json').read_text())
allocation = json.loads(Path('assets/data/hermes-flamepy-first-use-20261028.json').read_text())
plt.rcParams.update({'font.size': 10, 'svg.fonttype': 'none', 'axes.spines.top': False, 'axes.spines.right': False})
colors = {'sandbox': '#586777', 'session': '#db7547'}
fig, (left, right) = plt.subplots(1, 2, figsize=(12, 5.4), gridspec_kw={'width_ratios': [1, 1.15]})
for i, phase in enumerate(('first', 'reuse')):
    row = next(r for r in allocation['summary'] if r['phase'] == phase)
    value = row['median_s'] * 1000
    lo, hi = (v * 1000 for v in row['range_s'])
    left.barh(i, value, height=.42, color=('#586777' if phase == 'first' else '#db7547'))
    left.errorbar(value, i, xerr=[[value-lo], [hi-value]], fmt='none', ecolor='#202b35', capsize=4)
    left.text(value + 30, i - .27, f'{value:.0f} ms', va='center', fontsize=11)
left.set_yticks([0, 1], ['New executor', 'Retained executor'])
left.set_xlim(0, max(r['range_s'][1] * 1000 for r in allocation['summary']) * 1.15)
left.set_xlabel('Milliseconds · median of 12 allocations')
left.set_title('Sandbox → first Python result', pad=17)

keys = [('sandbox', 'python'), ('session', 'python'), ('sandbox', 'shell'), ('session', 'shell')]
for i, (api, language) in enumerate(keys):
    row = next(r for r in data['warm_descriptive'] if r['api'] == api and r['language'] == language)
    value = row['median_of_round_medians_s'] * 1000
    values = [r['median_s'] * 1000 for r in data['warm_per_round'] if r['api'] == api and r['language'] == language]
    right.barh(i, value, height=.53, color=colors[api])
    right.errorbar(value, i, xerr=[[value-min(values)], [max(values)-value]], fmt='none', ecolor='#202b35', capsize=4)
    right.text(max(values) + .6, i, f'{value:.2f} ms', va='center')
right.set_yticks(range(4), ['Sandbox · Python', 'Session · Python', 'Sandbox · shell', 'Session · shell'])
right.set_xlim(0, 36)
right.set_xlabel('Milliseconds · median of six round medians')
right.set_title('Retained-worker round trips', pad=17)
for axis in (left, right):
    axis.invert_yaxis()
    axis.grid(axis='x', alpha=.17)
    axis.set_axisbelow(True)
    axis.spines['left'].set_visible(False)
    axis.tick_params(axis='y', length=0)
fig.suptitle('Flame agent SDK performance inside Kubernetes', fontsize=16, y=.98)
fig.text(.035, .085, 'Index alias prewarmed for allocation; warm calls use a platform pin. Allocation: 12 pairs; warm calls: 50/group/round.', fontsize=8.5, color='#52606a')
fig.text(.035, .035, 'Whiskers show observed round ranges. Direct in-cluster RPC remains included; Mac WAN, Hermes and LLM time are excluded.', fontsize=8.5, color='#52606a')
fig.tight_layout(rect=(0, .14, 1, .92), w_pad=3)
directory = Path('assets/images/hermes-flamepy')
for extension in ('svg', 'png'):
    path = directory / ('agent-sdk-prewarmed-performance.' + extension)
    fig.savefig(path, dpi=180, facecolor='white')
    if extension == 'svg':
        path.write_text('\n'.join(line.rstrip() for line in path.read_text().splitlines()) + '\n')
plt.close(fig)
