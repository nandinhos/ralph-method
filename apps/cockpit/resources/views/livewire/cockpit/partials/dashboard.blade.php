@php
    $percent = (int) ($hud['percent'] ?? $workflow->progress_percent);
    $offset = 490.1 * (1 - max(0, min(100, $percent)) / 100);
    $featureSlotPercent = (int) ($hud['feature_slot_percent'] ?? $percent);
    $currentGates = $current ? ($gates[$current->feature_key] ?? collect()) : collect();
    $heroTitle = trim((string) ($launch['next_title'] ?? ''));
    $heroWords = preg_split('/\s+/u', $heroTitle, -1, PREG_SPLIT_NO_EMPTY) ?: [];
    $heroLast = count($heroWords) > 1 ? array_pop($heroWords) : null;
    $tone = in_array($tone ?? 'ok', ['ok', 'attention', 'lock'], true) ? $tone : 'ok';
@endphp

<section class="rt-hero is-{{ $tone }}">
    <div class="rt-hero-copy">
        <p class="rt-eyebrow">Workflow · {{ $workflow->workflow_id }}</p>
        <h1>
            @if ($launch['next_feature'])
                <span class="rt-hero-key">{{ $launch['next_feature'] }}</span>
                @if ($heroLast)
                    {{ implode(' ', $heroWords) }} <em>{{ $heroLast }}</em>
                @else
                    {{ $heroTitle !== '' ? $heroTitle : $launch['next_feature'] }}
                @endif
            @elseif ($launch['running'])
                {!! __('cockpit.hero.running_title') !!}
            @else
                {!! __('cockpit.hero.queue_empty_title') !!}
            @endif
        </h1>
        <x-runtime-chips :runtime="$runtime" />
        <div class="rt-run-row">
            @if ($launch['running'])
                <button type="button" class="rt-btn rt-btn-primary rt-btn-run is-running" disabled>
                    <span class="rt-spinner"></span>
                    {{ __('cockpit.run.running') }}
                </button>
                @if ($launch['pauseable'])
                    <button
                        type="button"
                        class="rt-btn rt-btn-pause"
                        wire:click="pauseRalph"
                        wire:loading.attr="disabled"
                        wire:target="pauseRalph"
                    >
                        <span wire:loading.remove wire:target="pauseRalph">{{ __('cockpit.run.pause') }}</span>
                        <span wire:loading wire:target="pauseRalph">{{ __('cockpit.run.pausing') }}</span>
                    </button>
                @endif
            @else
                @if ($launch['can_debug'] ?? false)
                    <button
                        type="button"
                        class="rt-btn rt-btn-admin"
                        wire:click="debugRalph"
                        wire:loading.attr="disabled"
                        wire:target="debugRalph"
                    >
                        <span wire:loading.remove wire:target="debugRalph">{{ __('cockpit.run.debug') }}</span>
                        <span wire:loading wire:target="debugRalph"><span class="rt-spinner"></span>{{ __('cockpit.run.debugging') }}</span>
                    </button>
                @endif
                @if ($launch['can_resume'] ?? false)
                    <button
                        type="button"
                        class="rt-btn rt-btn-primary rt-btn-run"
                        wire:click="resumeRalph"
                        wire:loading.attr="disabled"
                        wire:target="resumeRalph"
                    >
                        <span wire:loading.remove wire:target="resumeRalph">{{ __('cockpit.run.resume') }}</span>
                        <span wire:loading wire:target="resumeRalph"><span class="rt-spinner"></span>{{ __('cockpit.run.resuming') }}</span>
                    </button>
                @else
                    <button
                        type="button"
                        class="rt-btn rt-btn-primary rt-btn-run"
                        wire:click="startRalph"
                        @disabled(! $launch['ready'])
                        wire:loading.attr="disabled"
                        wire:target="startRalph"
                    >
                        <span wire:loading.remove wire:target="startRalph">{{ __('cockpit.run.cta') }}</span>
                        <span wire:loading wire:target="startRalph"><span class="rt-spinner"></span>{{ __('cockpit.run.starting') }}</span>
                    </button>
                @endif
            @endif
            <p class="rt-run-reason is-{{ $tone }} {{ $launchNoticeKind === 'ok' ? 'is-ok' : ($launchNoticeKind === 'blocked' ? 'is-off' : '') }}">{{ __($launchNotice !== '' ? $launchNotice : $launch['reason']) }}</p>
        </div>
        @if (($diagnosis['symptom'] ?? '') !== '')
            <article class="rt-diagnosis">
                <p class="rt-eyebrow">{{ $diagnosis['incident_id'] !== '' ? $diagnosis['incident_id'] : __('cockpit.diagnosis.title') }}</p>
                <h2>{{ __('cockpit.diagnosis.title') }}</h2>
                <p><strong>{{ __('cockpit.diagnosis.symptom') }}</strong> {{ $diagnosis['symptom'] }}</p>
                @if (($diagnosis['root_cause'] ?? '') !== '')
                    <p><strong>{{ __('cockpit.diagnosis.root_cause') }}</strong> {{ $diagnosis['root_cause'] }}</p>
                @endif
                @if (($diagnosis['correction_plan'] ?? '') !== '')
                    <p><strong>{{ __('cockpit.diagnosis.plan') }}</strong> {{ $diagnosis['correction_plan'] }}</p>
                @endif
                @if (($diagnosis['errors'] ?? []) !== [])
                    <ul>
                        @foreach ($diagnosis['errors'] as $error)
                            <li>{{ $error }}</li>
                        @endforeach
                    </ul>
                @endif
            </article>
        @endif
        <div class="rt-meta">
            <div>
                <p class="rt-eyebrow">{{ __('cockpit.meta.engine') }}</p>
                <code>{{ $workflow->engine ?: '—' }}</code>
            </div>
            <div>
                <p class="rt-eyebrow">{{ __('cockpit.meta.last_event') }}</p>
                <strong>{{ $workflow->last_event_at?->diffForHumans() ?? '—' }}</strong>
            </div>
            <div>
                <p class="rt-eyebrow">{{ __('cockpit.meta.authority') }}</p>
                <strong class="text-rt-violet">ralph-control · root</strong>
            </div>
        </div>
    </div>
    <div class="rt-hero-side">
        <div class="rt-ring">
            <svg width="196" height="196" viewBox="0 0 196 196">
                <defs>
                    <linearGradient id="rtHudGrad" x1="0" y1="1" x2="1" y2="0">
                        <stop offset="0" stop-color="var(--rt-hud-from)"></stop>
                        <stop offset="1" stop-color="var(--rt-hud-to)"></stop>
                    </linearGradient>
                </defs>
                <circle cx="98" cy="98" r="92" fill="none" stroke="var(--rt-hud-track)" stroke-width="1" stroke-dasharray="2 10"></circle>
                <circle cx="98" cy="98" r="78" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="10"></circle>
                <circle cx="98" cy="98" r="78" fill="none" stroke="url(#rtHudGrad)" stroke-width="10" stroke-linecap="round" stroke-dasharray="490.1" stroke-dashoffset="{{ $offset }}" transform="rotate(-90 98 98)"></circle>
            </svg>
            <div class="rt-ring-value">
                <strong>{{ $percent }}%</strong>
                <span>{{ ($hud['label'] ?? 'workflow') === 'ativo' ? __('cockpit.progress.active') : __('cockpit.progress.workflow') }}</span>
            </div>
        </div>
        <p class="rt-mono">attempt {{ $workflow->attempt ?: '—' }} · {{ $workflow->engine ?: '—' }}</p>
        @if (($hud['detail'] ?? '') !== '')
            <p class="rt-muted rt-progress-detail">{{ $hud['detail'] }}</p>
        @endif
    </div>
</section>

<section class="rt-metrics">
    <article class="rt-card">
        <div class="rt-metric-label"><span>{{ __('cockpit.metrics.features') }}</span></div>
        <div class="rt-metric-value">{{ $features->where('status', 'released')->count() }} <small>/ {{ $features->count() }}</small></div>
        <div class="rt-muted">{{ $current ? __('cockpit.metrics.one_running') : __('cockpit.metrics.idle') }}</div>
    </article>
    <article class="rt-card">
        <div class="rt-metric-label"><span>{{ __('cockpit.metrics.gates') }}</span></div>
        <div class="rt-metric-value text-rt-lime">{{ $gates->flatten()->where('status', 'passed')->count() }}</div>
        <div class="rt-muted">{{ __('cockpit.metrics.gates_note') }}</div>
    </article>
    <article class="rt-card">
        <div class="rt-metric-label"><span>{{ __('cockpit.metrics.live') }}</span><span class="text-rt-cyan">{{ __('cockpit.metrics.live_tag') }}</span></div>
        <div class="rt-metric-value rt-mono">{{ $workflow->started_at?->diffForHumans() ?? '—' }}</div>
        <div class="rt-muted">{{ __('cockpit.metrics.since_start') }}</div>
    </article>
    <article class="rt-card">
        <div class="rt-metric-label"><span>{{ __('cockpit.metrics.recovery') }}</span></div>
        <div class="rt-metric-value {{ $workflow->recovery_count > 0 ? 'text-rt-amber' : '' }}">{{ $workflow->recovery_count }}</div>
        <div class="rt-muted">{{ __('cockpit.metrics.recovery_note') }}</div>
    </article>
</section>

@if ($filter === 'all')
    <section class="rt-grid">
        <div class="rt-card">
            <div class="rt-section-title">
                <h2>{{ __('cockpit.current.title') }}</h2>
                <span class="rt-mono">attempt {{ $current?->attempt ?: $workflow->attempt ?: '—' }} · {{ $current?->engine ?: $workflow->engine ?: '—' }}</span>
            </div>
            @if ($current)
                <div class="rt-feature">
                    <div class="rt-feature-meta">
                        <span class="rt-key">{{ $current->feature_key }}</span>
                        <span class="rt-status"><i class="rt-pulse"></i> {{ $current->status }}</span>
                    </div>
                    <div class="rt-feature-title">{{ $current->title ?: $current->feature_key }}</div>
                    <div class="rt-track"><div class="rt-bar" style="width: {{ max($featureSlotPercent, $percent) }}%"></div></div>
                </div>
            @endif
            <div class="rt-section-title" style="margin-top: 26px">
                <h2>{{ __('cockpit.sequence.title') }}</h2>
                <span>{{ __('cockpit.sequence.note') }}</span>
            </div>
            <div class="rt-tree">
                @foreach ($features as $feature)
                    <div class="rt-node {{ $current && $feature->feature_key === $current->feature_key ? 'is-current' : '' }}">
                        <span class="rt-icon">{{ $feature->status === 'released' ? '✓' : ($feature->status === 'running' ? '→' : '○') }}</span>
                        <div>
                            <strong>{{ $feature->feature_key }} · {{ $feature->title }}</strong>
                            <small class="rt-mono">{{ $feature->status }} · {{ $feature->engine ?: '—' }}</small>
                        </div>
                        <span class="rt-state">{{ $feature->status }}</span>
                    </div>
                @endforeach
            </div>
        </div>

        <div class="rt-card">
            <div class="rt-section-title">
                <h2>{{ __('cockpit.gates.title') }}</h2>
                <span>{{ __('cockpit.gates.note') }}</span>
            </div>
            <div class="rt-gates">
                @foreach ($gateKeys as $gateKey)
                    @php
                        $gate = $currentGates->firstWhere('gate_key', $gateKey);
                        $gateStatus = $gate?->status ?? 'pending';
                        $gateVisual = \App\Ralph\GateCatalog::visualClass($gateStatus);
                    @endphp
                    <div class="rt-gate">
                        <div class="rt-gate-left">
                            <span class="rt-dot {{ $gateVisual }}">{{ \App\Ralph\GateCatalog::gateSymbol($gateStatus) }}</span>
                            <div>
                                <div class="rt-gate-name">{{ \App\Ralph\GateCatalog::label($gateKey) }}</div>
                                <div class="rt-muted">{{ $gate?->detail ?: $gateKey }}</div>
                            </div>
                        </div>
                        <span class="rt-badge {{ $gateVisual }}">{{ $gateStatus }}</span>
                    </div>
                @endforeach
            </div>
        </div>

        <div class="rt-card">
            <div class="rt-section-title">
                <h2>{{ __('cockpit.timeline.title') }}</h2>
                <span>{{ __('cockpit.timeline.note') }}</span>
            </div>
            <div class="rt-timeline">
                @foreach ($events->take(8) as $event)
                    <div class="rt-event">
                        <span class="rt-marker {{ $event->kind === 'gates' ? 'is-lime' : '' }}"></span>
                        <div class="rt-event-main">
                            <div>
                                <div class="rt-event-name">{{ $event->name }}</div>
                                <div class="rt-muted">{{ $event->detail }}</div>
                            </div>
                            <span class="rt-mono">{{ $event->occurred_at?->format('H:i:s') }}</span>
                        </div>
                    </div>
                @endforeach
            </div>
        </div>

        <div class="rt-card">
            <div class="rt-section-title">
                <h2>{{ __('cockpit.memory.title') }}</h2>
                <span>{{ __('cockpit.memory.note') }}</span>
            </div>
            <div class="rt-memory">
                @forelse ($knowledge as $item)
                    <div class="rt-memory-item">
                        <span>✦</span>
                        <div>
                            <strong>{{ $item->title }}</strong>
                            <small class="rt-mono">{{ $item->subtitle }}</small>
                        </div>
                        <span class="rt-badge {{ $item->status === 'pending' ? 'is-wait' : 'is-ok' }}">{{ $item->status }}</span>
                    </div>
                @empty
                    <p class="rt-muted">{{ __('cockpit.memory.empty') }}</p>
                @endforelse
            </div>
            <div class="rt-section-title" style="margin-top: 24px">
                <h2>{{ __('cockpit.delegation.title') }}</h2>
                <span>{{ __('cockpit.delegation.note') }}</span>
            </div>
            <div class="rt-tree">
                @foreach ($delegations as $node)
                    <div class="rt-node {{ $node->role !== 'root' ? 'is-child' : 'is-root' }}">
                        <span class="rt-icon">{{ strtoupper(substr($node->label, 0, 1)) }}</span>
                        <div>
                            <strong>{{ $node->label }}</strong>
                            <small>{{ $node->detail }}</small>
                        </div>
                        <span class="rt-state">{{ $node->state }}</span>
                    </div>
                @endforeach
            </div>
        </div>
    </section>
@elseif ($filter === 'events')
    <section class="rt-card">
        <div class="rt-section-title">
            <h2>{{ __('cockpit.log.title') }}</h2>
            <span>{{ $events->count() }} · {{ __('cockpit.timeline.note') }}</span>
        </div>
        @forelse ($events as $event)
            <div class="rt-log-row">
                <span class="rt-mono">{{ $event->occurred_at?->format('H:i:s') }}</span>
                <span class="rt-marker {{ $event->kind === 'gates' ? 'is-lime' : '' }}"></span>
                <div>
                    <div class="rt-event-name">{{ $event->name }}</div>
                    <div class="rt-muted">{{ $event->detail }}</div>
                </div>
                <span class="rt-badge">{{ $event->kind }}</span>
            </div>
        @empty
            <p class="rt-muted">{{ __('cockpit.timeline.empty') }}</p>
        @endforelse
    </section>
@else
    <section class="rt-gates-board">
        @foreach ($features as $feature)
            <div class="rt-card">
                <div class="rt-feature-meta">
                    <span class="rt-key">{{ $feature->feature_key }}</span>
                    <span class="rt-badge">{{ $feature->status }}</span>
                </div>
                <div class="rt-feature-title">{{ $feature->title }}</div>
                @foreach ($gateKeys as $gateKey)
                    @php
                        $gate = ($gates[$feature->feature_key] ?? collect())->firstWhere('gate_key', $gateKey);
                        $gateStatus = $gate?->status ?? 'pending';
                        $gateVisual = \App\Ralph\GateCatalog::visualClass($gateStatus);
                    @endphp
                    <div class="rt-gate">
                        <div class="rt-gate-left">
                            <span class="rt-dot {{ $gateVisual }}">{{ \App\Ralph\GateCatalog::gateSymbol($gateStatus) }}</span>
                            <div class="rt-gate-name">{{ \App\Ralph\GateCatalog::label($gateKey) }}</div>
                        </div>
                        <span class="rt-badge {{ $gateVisual }}">{{ $gateStatus }}</span>
                    </div>
                @endforeach
            </div>
        @endforeach
    </section>
@endif
