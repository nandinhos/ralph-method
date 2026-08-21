<div class="rt-shell" wire:poll.5s>
    <header class="rt-topbar">
        <div class="rt-brand">
            <div class="rt-mark">R</div>
            <div>
                <p class="rt-eyebrow">{{ __('cockpit.eyebrow') }}</p>
                <div class="rt-name">RALPH-<span>METHOD</span></div>
            </div>
        </div>
        <div class="rt-actions">
            <div class="rt-status">
                <i class="rt-pulse"></i>
                {{ __('cockpit.health.'.($workflow?->health ?? 'unknown')) }}
            </div>
            <div class="rt-filters">
                <button type="button" class="rt-btn {{ $filter === 'all' ? 'is-on' : '' }}" wire:click="setFilter('all')">{{ __('cockpit.filter.all') }}</button>
                <button type="button" class="rt-btn {{ $filter === 'events' ? 'is-on' : '' }}" wire:click="setFilter('events')">{{ __('cockpit.filter.events') }}</button>
                <button type="button" class="rt-btn {{ $filter === 'gates' ? 'is-on' : '' }}" wire:click="setFilter('gates')">{{ __('cockpit.filter.gates') }}</button>
            </div>
            <button type="button" class="rt-btn rt-btn-primary" wire:click="refreshSnapshot">{{ __('cockpit.refresh') }}</button>
        </div>
    </header>

    @if ($workflow === null)
        <section class="rt-card rt-empty">
            <p class="rt-eyebrow">{{ __('cockpit.empty.kicker') }}</p>
            <h1>{{ __('cockpit.empty.title') }}</h1>
            <p>{{ __('cockpit.empty.body') }}</p>
            <x-runtime-chips :runtime="$runtime" />
            <div class="rt-run-row">
                <button type="button" class="rt-btn rt-btn-primary rt-btn-run" disabled>{{ __('cockpit.run.cta') }}</button>
                <p class="rt-run-reason">{{ __($launch['reason']) }}</p>
            </div>
            <code>php artisan ralph:ingest --rebuild --follow</code>
        </section>
    @else
        @include('livewire.cockpit.partials.dashboard')
    @endif

    <p class="rt-footer">{{ __('cockpit.footer') }}</p>
</div>
